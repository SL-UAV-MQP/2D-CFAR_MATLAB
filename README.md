These folders contain all of the finalized code required to interface and operate a Keysight N9310A RF Signal Generator, Agilent CSA 1996A Spectrum Analyzer, and MATLAB for the purposes of determining the beampattern of a prototype antenna.

This interface is intended to be performed with a computer running Keysight Connection Expert and MATLAB with the Instrument Control Toolbox and the Instrument Control Toolbox Support Package for Keysight IO Libraries and VISA Interface support package.

USB (as is native to the Keysight N9310A RF Signal Generator) and Ethernet (as is native to the Agilent CSA 1996A Spectrum Analyzer)peripherals are required for this software to function, as well as a "dumb" network switch with statically assigned IP addresses.

This repository DOES NOT include code required to interface the ADALM-PLUTO Rev C SDRs with the Raspberry Pi 5B nor with the LSM6DSO IMU, LIS3MDL Magnetometer, MS5607-02BA03 Altimeter, Digi XBee 3 Pro, nor Radio Frequency Front End boards.

Code for interfacing the ADALM-PLUTO Rev C SDRs with the Raspberry Pi 5B can be found at:

https://github.com/SL-UAV-MQP/pi_C_code2 
https://github.com/SL-UAV-MQP/pi_C_code

Code for interfacing the LSM6DSO IMU, LIS3MDL Magnetometer, MS5607-02BA03 Altimeter, Digi XBee 3 Pro, and Radio Frequency Front End boards with the Raspberry Pi 5B can be found at:

https://github.com/SL-UAV-MQP/Attitude_Sensor_Telemetry_GPIO_Testsets

All code in this repository and related repositories is a portion of materials for a Major Qualifying Project (MQP), submitted to the faculty of Worcester Polytechnic Institute (WPI) in partial fulfillment of the requirements for the Degree of Bachelor of Science in Electrical and Computer Engineering, as completed by John Frahm, Carthene McTague, Ann Phan, Heath Sainio, and John Song.
