classdef CFAR2D < handle
    % CFAR2D - 2D Order-Statistic CFAR Detector
    % ==========================================
    %
    % Implements adaptive thresholding for MUSIC AOA validation
    % in multipath environments. Optimized for real-time processing.
    %
    % Based on OS-CFAR (Order-Statistic Constant False Alarm Rate)
    %
    % Author: Ported from Python implementation
    % Date: 2025-12-08

    properties
        % Window dimensions
        window_size = [9, 9]  % [azimuth, elevation/freq]
        guard_size = [3, 3]   % Guard cells around CUT

        % OS-CFAR parameters
        k_factor = 0.75  % Order statistic selection (0-1)
        pfa = 1e-4       % Probability of false alarm
        threshold_offset_db = 3.0  % Additional margin in dB

        % Detection parameters
        min_snr_db = 10.0  % Minimum SNR for detection
        edge_handling = 'constant'  % 'constant', 'symmetric', 'circular'

        % Precomputed properties
        training_mask
        n_training_cells
    end

    methods
        function obj = CFAR2D(varargin)
            % Constructor
            %
            % Usage:
            %   cfar = CFAR2D()
            %   cfar = CFAR2D('window_size', [11, 7], 'k_factor', 0.7)

            % Parse optional inputs
            p = inputParser;
            addParameter(p, 'window_size', [9, 9]);
            addParameter(p, 'guard_size', [3, 3]);
            addParameter(p, 'k_factor', 0.75);
            addParameter(p, 'pfa', 1e-4);
            addParameter(p, 'threshold_offset_db', 3.0);
            addParameter(p, 'min_snr_db', 10.0);
            addParameter(p, 'edge_handling', 'constant');
            parse(p, varargin{:});

            obj.window_size = p.Results.window_size;
            obj.guard_size = p.Results.guard_size;
            obj.k_factor = p.Results.k_factor;
            obj.pfa = p.Results.pfa;
            obj.threshold_offset_db = p.Results.threshold_offset_db;
            obj.min_snr_db = p.Results.min_snr_db;
            obj.edge_handling = p.Results.edge_handling;

            % Validate configuration
            obj.validate_config();

            % Precompute training mask
            obj.create_training_mask();

            fprintf('CFAR2D initialized:\n');
            fprintf('  Window size: [%d, %d]\n', obj.window_size);
            fprintf('  Guard size: [%d, %d]\n', obj.guard_size);
            fprintf('  Training cells: %d\n', obj.n_training_cells);
            fprintf('  k-factor: %.2f\n', obj.k_factor);
        end

        function validate_config(obj)
            % Validate configuration parameters

            % Check odd window size
            if mod(obj.window_size(1), 2) == 0 || mod(obj.window_size(2), 2) == 0
                error('Window size must be odd in both dimensions');
            end

            % Check guard size
            if obj.guard_size(1) >= floor(obj.window_size(1)/2) || ...
                    obj.guard_size(2) >= floor(obj.window_size(2)/2)
                error('Guard size must be smaller than half window size');
            end

            % Check k-factor
            if obj.k_factor <= 0 || obj.k_factor >= 1
                error('k_factor must be between 0 and 1');
            end
        end

        function create_training_mask(obj)
            % Create binary mask for training cells (excludes CUT and guard)

            h = obj.window_size(1);
            w = obj.window_size(2);
            gh = obj.guard_size(1);
            gw = obj.guard_size(2);

            mask = true(h, w);

            % Center indices
            ch = ceil(h / 2);
            cw = ceil(w / 2);

            % Zero out guard cells and CUT
            mask(ch-gh:ch+gh, cw-gw:cw+gw) = false;

            obj.training_mask = mask;

            % Count training cells
            obj.n_training_cells = sum(mask(:));

            if obj.n_training_cells < 10
                warning('Very few training cells (%d). Consider larger window.', ...
                    obj.n_training_cells);
            end
        end

        function results = detect(obj, spectrum, noise_floor_db)
            % Apply 2D OS-CFAR detection to spatial spectrum
            %
            % Inputs:
            %   spectrum: (n_azimuth × n_elevation) 2D spectrum in dB
            %   noise_floor_db: Known noise floor (optional)
            %
            % Returns:
            %   results: struct with fields:
            %     - detections: Binary detection mask
            %     - threshold: Adaptive threshold (dB)
            %     - snr: Estimated SNR at each position (dB)
            %     - noise_floor: Estimated noise floor (dB)
            %     - n_detections: Number of detections
            %     - peak_snr: Maximum SNR

            % Validate input
            if ndims(spectrum) ~= 2
                error('Input spectrum must be 2D array');
            end

            % Check if input is in dB or linear
            if all(spectrum(:) <= 0)
                % Likely in dB, convert to linear
                spectrum_linear = 10 .^ (spectrum / 10.0);
                input_was_db = true;
            else
                spectrum_linear = spectrum;
                input_was_db = false;
            end

            % Compute adaptive threshold
            threshold_linear = obj.compute_threshold(spectrum_linear);

            % Apply detection
            detections = spectrum_linear > threshold_linear;

            % Convert back to dB
            spectrum_db = 10 * log10(spectrum_linear + 1e-12);
            threshold_db = 10 * log10(threshold_linear + 1e-12);

            % Estimate noise floor
            if nargin < 3 || isempty(noise_floor_db)
                noise_floor_db = obj.estimate_noise_floor(spectrum_db);
            end

            % Compute SNR
            snr_db = spectrum_db - noise_floor_db;

            % Apply minimum SNR threshold
            detections = detections & (snr_db >= obj.min_snr_db);

            % Package results
            results = struct();
            results.detections = detections;
            results.threshold = threshold_db;
            results.snr = snr_db;
            results.noise_floor = noise_floor_db;
            results.n_detections = sum(detections(:));
            results.peak_snr = max(snr_db(:));
        end

        function threshold = compute_threshold(obj, spectrum)
            % Compute adaptive threshold using OS-CFAR
            %
            % Inputs:
            %   spectrum: 2D spectrum in linear power
            %
            % Returns:
            %   threshold: Adaptive threshold in linear power

            [h, w] = size(spectrum);
            wh = obj.window_size(1);
            ww = obj.window_size(2);

            % Pad spectrum for edge handling
            pad_h = floor(wh / 2);
            pad_w = floor(ww / 2);

            if strcmp(obj.edge_handling, 'circular')
                % Wrap around for azimuth
                spectrum_padded = padarray(spectrum, [pad_h, pad_w], 'circular');
            elseif strcmp(obj.edge_handling, 'symmetric')
                spectrum_padded = padarray(spectrum, [pad_h, pad_w], 'symmetric');
            else  % constant
                spectrum_padded = padarray(spectrum, [pad_h, pad_w], ...
                    'constant', median(spectrum(:)));
            end

            % Initialize threshold array
            threshold = zeros(h, w);

            % Calculate k-th order statistic index
            k_index = round(obj.k_factor * obj.n_training_cells);

            % Sliding window
            for i = 1:h
                for j = 1:w
                    % Extract window
                    window = spectrum_padded(i:i+wh-1, j:j+ww-1);

                    % Extract training cells using mask
                    training_vals = window(obj.training_mask);

                    % Sort and select k-th order statistic
                    training_sorted = sort(training_vals);
                    threshold_val = training_sorted(k_index);

                    % Apply scaling factor
                    threshold(i, j) = threshold_val * obj.compute_scale_factor();
                end
            end
        end

        function scale = compute_scale_factor(obj)
            % Compute CFAR scale factor based on Pfa
            %
            % Returns:
            %   scale: Multiplicative scale factor

            n_train = obj.n_training_cells;
            pfa = obj.pfa;

            % Approximation: α = N_train * (Pfa^(-1/N_train) - 1)
            alpha = n_train * (pfa ^ (-1 / n_train) - 1);

            % Add user-defined offset
            offset_linear = 10 ^ (obj.threshold_offset_db / 10.0);

            scale = alpha * offset_linear;
        end

        function noise_floor_db = estimate_noise_floor(~, spectrum_db)
            % Estimate noise floor from spectrum using robust statistics
            %
            % Inputs:
            %   spectrum_db: Spectrum in dB
            %
            % Returns:
            %   noise_floor_db: Estimated noise floor in dB

            % Convert to real if complex
            if ~isreal(spectrum_db)
                spectrum_db = abs(spectrum_db);
            end

            % Use lower percentile to avoid signal contamination
            noise_floor_db = prctile(spectrum_db(:), 10);
        end

        function peaks = extract_peaks(obj, spectrum, detection_mask, ...
                azimuth_grid, elevation_grid)
            % Extract peak locations and properties from detection mask
            %
            % Inputs:
            %   spectrum: Original spectrum in dB
            %   detection_mask: Binary detection mask from CFAR
            %   azimuth_grid: Azimuth angles (degrees)
            %   elevation_grid: Elevation angles (optional)
            %
            % Returns:
            %   peaks: struct with fields:
            %     - azimuth, elevation, power, snr, indices

            % Find peak indices
            [peak_rows, peak_cols] = find(detection_mask);

            if isempty(peak_rows)
                peaks = struct();
                peaks.azimuth = [];
                peaks.elevation = [];
                peaks.power = [];
                peaks.snr = [];
                peaks.indices = [];
                return;
            end

            % Extract peak properties
            peak_azimuths = azimuth_grid(peak_rows);
            peak_powers = zeros(length(peak_rows), 1);
            for i = 1:length(peak_rows)
                peak_powers(i) = spectrum(peak_rows(i), peak_cols(i));
            end

            if nargin >= 5 && ~isempty(elevation_grid)
                peak_elevations = elevation_grid(peak_cols);
            else
                peak_elevations = zeros(size(peak_azimuths));
            end

            % Estimate SNR
            noise_floor = obj.estimate_noise_floor(spectrum);
            peak_snrs = peak_powers - noise_floor;

            % Sort by power (descending)
            [~, sort_idx] = sort(peak_powers, 'descend');

            % Package results
            peaks = struct();
            peaks.azimuth = peak_azimuths(sort_idx);
            peaks.elevation = peak_elevations(sort_idx);
            peaks.power = peak_powers(sort_idx);
            peaks.snr = peak_snrs(sort_idx);
            peaks.indices = [peak_rows(sort_idx), peak_cols(sort_idx)];
        end
    end

    methods (Static)
        function config = cmrcm_config()
            % Create CFAR configuration optimized for CMRCM field
            %
            % Returns:
            %   config: Cell array for CFAR2D constructor

            config = {
                'window_size', [11, 7], ...
                'guard_size', [3, 2], ...
                'k_factor', 0.7, ...
                'pfa', 1e-4, ...
                'threshold_offset_db', 2.5, ...
                'min_snr_db', 10.0, ...
                'edge_handling', 'circular'
            };
        end

        function suppressed = apply_nms_2d(detections, spectrum, window_size)
            % Apply Non-Maximum Suppression to eliminate close detections
            %
            % Inputs:
            %   detections: Binary detection mask
            %   spectrum: Original spectrum (for selecting maxima)
            %   window_size: Suppression window size (default 5)
            %
            % Returns:
            %   suppressed: Detection mask after NMS

            if nargin < 3
                window_size = 5;
            end

            % Find local maxima
            max_filtered = ordfilt2(spectrum, window_size^2, ...
                ones(window_size, window_size));
            local_maxima = (spectrum == max_filtered);

            % Keep only detections that are also local maxima
            suppressed = detections & local_maxima;
        end
    end
end
