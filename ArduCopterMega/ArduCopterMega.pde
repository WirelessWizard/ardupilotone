// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: t -*-

/*
ArduCopterMega Version 0.1 Experimental
Authors:	Jason Short
Based on code and ideas from the Arducopter team: Jose Julio, Randy Mackay, Jani Hirvinen
Thanks to:	Chris Anderson, Mike Smith, Jordi Munoz, Doug Weibel, James Goppert, Benjamin Pelletier

This firmware is free software; you can redistribute it and / or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.
*/

// AVR runtime
#include <avr/io.h>
#include <avr/eeprom.h>
#include <avr/pgmspace.h>
#include <math.h>

// Libraries
#include <FastSerial.h>
#include <AP_Common.h>
#include <APM_RC.h> 		// ArduPilot Mega RC Library
#include <RC_Channel.h> 	// ArduPilot Mega RC Library
#include <AP_ADC.h>			// ArduPilot Mega Analog to Digital Converter Library 
#include <AP_GPS.h>			// ArduPilot GPS library
#include <Wire.h>			// Arduino I2C lib
#include <APM_BMP085.h> 	// ArduPilot Mega BMP085 Library 
#include <DataFlash.h>		// ArduPilot Mega Flash Memory Library
#include <AP_Compass_HMC5843.h>	// ArduPilot Mega Magnetometer Library
#include <AP_Math.h>		// ArduPilot Mega Vector/Matrix math Library
#include <AP_IMU.h>			// ArduPilot Mega IMU Library
#include <AP_DCM.h>		// ArduPilot Mega DCM Library
#include <PID.h> 			// ArduPilot Mega RC Library


// Configuration
#include "config.h"

// Local modules
#include "defines.h"

// Serial ports
//
// Note that FastSerial port buffers are allocated at ::begin time,
// so there is not much of a penalty to defining ports that we don't
// use.

FastSerialPort0(Serial);		// FTDI/console
FastSerialPort1(Serial1);		// GPS port (except for GPS_PROTOCOL_IMU)
FastSerialPort3(Serial3);		// Telemetry port (optional, Standard and ArduPilot protocols only)

// standard sensors for live flight
AP_ADC_ADS7844 		adc;
APM_BMP085_Class	APM_BMP085;
AP_Compass_HMC5843	compass;


// GPS selection
#if   GPS_PROTOCOL == GPS_PROTOCOL_NMEA
AP_GPS_NMEA		GPS(&Serial1);
#elif GPS_PROTOCOL == GPS_PROTOCOL_SIRF
AP_GPS_SIRF		GPS(&Serial1);
#elif GPS_PROTOCOL == GPS_PROTOCOL_UBLOX
AP_GPS_UBLOX	GPS(&Serial1);
#elif GPS_PROTOCOL == GPS_PROTOCOL_IMU
AP_GPS_IMU		GPS(&Serial);	// note, console port
#elif GPS_PROTOCOL == GPS_PROTOCOL_MTK
AP_GPS_MTK		GPS(&Serial1);
#elif GPS_PROTOCOL == GPS_PROTOCOL_NONE
AP_GPS_NONE		GPS(NULL);
#else
# error Must define GPS_PROTOCOL in your configuration file.
#endif

AP_IMU 		imu(&adc, EE_IMU_OFFSET);
AP_DCM 		dcm(&imu, &GPS);


// GENERAL VARIABLE DECLARATIONS
// --------------------------------------------

byte 	control_mode		= STABILIZE;
boolean failsafe			= false;		// did our throttle dip below the failsafe value?
boolean ch3_failsafe		= false;
byte 	oldSwitchPosition;					// for remembering the control mode switch

const char *comma = ",";

byte flight_modes[6];
const char* flight_mode_strings[] = {
	"ACRO",
	"STABILIZE",
	"ALT_HOLD",
	"AUTO",
	"POSITION_HOLD",
	"RTL",
	"TAKEOFF",
	"LAND"};

/* Radio values
		Channel assignments	
			1	Ailerons (rudder if no ailerons)
			2	Elevator
			3	Throttle
			4	Rudder (if we have ailerons)
			5	Mode - 3 position switch
			6 	Altitude for Hold, user assignable
			7	trainer switch - sets throttle nominal (toggle switch), sets accels to Level (hold > 1 second)
			8	TBD
*/

// Radio
// -----
RC_Channel rc_1(EE_RADIO_1);
RC_Channel rc_2(EE_RADIO_2);
RC_Channel rc_3(EE_RADIO_3);
RC_Channel rc_4(EE_RADIO_4);
RC_Channel rc_5(EE_RADIO_5);
RC_Channel rc_6(EE_RADIO_6);
RC_Channel rc_7(EE_RADIO_7);
RC_Channel rc_8(EE_RADIO_8);
int motor_out[4];
byte flight_mode_channel;
byte frame_type = PLUS_FRAME;

// PIDs and gains
// ---------------

//Acro
PID pid_acro_rate_roll		(EE_GAIN_1);
PID pid_acro_rate_pitch		(EE_GAIN_2);
PID pid_acro_rate_yaw		(EE_GAIN_3);
float 	acro_rate_roll_pitch, acro_rate_yaw;

//Stabilize
PID pid_stabilize_roll		(EE_GAIN_4);
PID pid_stabilize_pitch		(EE_GAIN_5);
PID pid_yaw					(EE_GAIN_6);
float 	stabilize_rate_roll_pitch;
float 	stabilize_rate_yaw;
float 	stabilze_dampener;
int 	max_stabilize_dampener;
float 	stabilze_yaw_dampener;
int 	max_yaw_dampener;

// Nav
PID pid_nav					(EE_GAIN_7);
PID pid_throttle			(EE_GAIN_8);

// GPS variables
// -------------
byte 	ground_start_count	= 5;			// have we achieved first lock and set Home?
const 	float t7			= 10000000.0;	// used to scale GPS values for EEPROM storage
float 	scaleLongUp;						// used to reverse longtitude scaling
float 	scaleLongDown;						// used to reverse longtitude scaling
boolean GPS_light			= false;		// status of the GPS light

// Location & Navigation 
// ---------------------
byte 	wp_radius			= 3;			// meters
long	nav_bearing;						// deg * 100 : 0 to 360 current desired bearing to navigate
long 	target_bearing;						// deg * 100 : 0 to 360 location of the plane to the target
long 	crosstrack_bearing;					// deg * 100 : 0 to 360 desired angle of plane to target
int 	climb_rate;							// m/s * 100  - For future implementation of controlled ascent/descent by rate
byte	loiter_radius; 						// meters
float	x_track_gain;
int		x_track_angle;

long	alt_to_hold;						// how high we should be for RTL
long 	nav_angle;
long	pitch_max;

byte	command_must_index;					// current command memory location
byte	command_may_index;					// current command memory location
byte	command_must_ID;					// current command ID
byte	command_may_ID;						// current command ID

float	altitude_gain;						// in nav
float	distance_gain;						// in nav

// Airspeed
// --------
int 	airspeed;							// m/s * 100

// Throttle Failsafe
// ------------------
boolean		motor_armed;
byte 		throttle_failsafe_enabled;
int 		throttle_failsafe_value;
byte 		throttle_failsafe_action;
uint16_t 	log_bitmask;

// Location Errors
// ---------------
long 	bearing_error;						// deg * 100 : 0 to 36000 
long 	altitude_error;						// meters * 100 we are off in altitude
float 	airspeed_error;						// m / s * 100 
float	crosstrack_error;					// meters we are off trackline
long 	distance_error;						// distance to the WP
long 	yaw_error;							// how off are we pointed

// Sensors
// -------
float	battery_voltage		= LOW_VOLTAGE * 1.05;		// Battery Voltage of total battery, initialized above threshold for filter
float 	battery_voltage1 	= LOW_VOLTAGE * 1.05;		// Battery Voltage of cell 1, initialized above threshold for filter
float 	battery_voltage2 	= LOW_VOLTAGE * 1.05;		// Battery Voltage of cells 1 + 2, initialized above threshold for filter
float 	battery_voltage3 	= LOW_VOLTAGE * 1.05;		// Battery Voltage of cells 1 + 2+3, initialized above threshold for filter
float 	battery_voltage4 	= LOW_VOLTAGE * 1.05;		// Battery Voltage of cells 1 + 2+3 + 4, initialized above threshold for filter

// Magnetometer variables
// ----------------------
int 	magnetom_x;
int 	magnetom_y;
int 	magnetom_z;
float 	MAG_Heading;

float 	mag_offset_x;
float 	mag_offset_y;
float 	mag_offset_z;
float 	mag_declination;
bool	compass_enabled;

// Barometer Sensor variables
// --------------------------
int				baro_offset;				// used to correct drift of absolute pressue sensor
unsigned long 	abs_pressure;
unsigned long 	abs_pressure_ground;
int 			ground_temperature;
int 			temp_unfilt;

// From IMU
// --------
long	roll_sensor;						// degrees * 100
long	pitch_sensor;						// degrees * 100
long	yaw_sensor;							// degrees * 100
float 	roll;								// radians
float 	pitch;								// radians
float 	yaw;								// radians

// flight mode specific
// --------------------
boolean takeoff_complete	= false;		// Flag for using take-off controls
boolean land_complete		= false;
int landing_pitch;							// pitch for landing set by commands
//int takeoff_pitch;			
int takeoff_altitude;		
int landing_distance;						// meters;

// Loiter management
// -----------------
long 	old_target_bearing;					// deg * 100
int		loiter_total; 						// deg : how many times to loiter * 360
int 	loiter_delta;						// deg : how far we just turned
int		loiter_sum;							// deg : how far we have turned around a waypoint
long 	loiter_time;						// millis : when we started LOITER mode
int 	loiter_time_max;					// millis : how long to stay in LOITER mode

// these are the values for navigation control functions
// ----------------------------------------------------
long 	nav_roll;							// deg * 100 : target roll angle
long 	nav_pitch;							// deg * 100 : target pitch angle
long 	nav_yaw;							// deg * 100 : target yaw angle
int 	nav_throttle;						// 0-1000 for throttle control

long 	command_yaw_start;					// what angle were we to begin with
long 	command_yaw_start_time;				// when did we start turning
int		command_yaw_time;					// how long we are turning
long 	command_yaw_end;					// what angle are we trying to be
long 	command_yaw_delta;					// how many degrees will we turn
int		command_yaw_speed;					// how fast to turn
byte	command_yaw_dir;
long 	old_alt;							// used for managing altitude rates
int		velocity_land;						

long	altitude_estimate;					// for smoothing GPS output
long	distance_estimate;					// for smoothing GPS output

int 	throttle_min;						// 0 - 1000 : Min throttle output - copter should be 0
int 	throttle_cruise;					// 0 - 1000 : what will make the copter hover
int 	throttle_max;						// 0 - 1000 : Max throttle output

// Waypoints
// ---------
long 	GPS_wp_distance;					// meters - distance between plane and next waypoint
long 	wp_distance;						// meters - distance between plane and next waypoint
long 	wp_totalDistance;					// meters - distance between old and next waypoint
byte 	wp_total;							// # of Commands total including way
byte 	wp_index;							// Current active command index
byte 	next_wp_index;						// Current active command index

// repeating event control
// -----------------------
byte 	event_id; 							// what to do - see defines
long 	event_timer; 						// when the event was asked for in ms
int 	event_delay; 						// how long to delay the next firing of event in millis
int 	event_repeat;						// how many times to fire : 0 = forever, 1 = do once, 2 = do twice
int 	event_value; 						// per command value, such as PWM for servos
int 	event_undo_value;					// the value used to undo commands
byte 	repeat_forever;						
byte 	undo_event;							// counter for timing the undo

// delay command
// --------------
int 	delay_timeout;						// used to delay commands
long 	delay_start;						// used to delay commands

// 3D Location vectors
// -------------------
struct Location home;						// home location
struct Location prev_WP;					// last waypoint
struct Location current_loc;				// current location
struct Location next_WP;					// next waypoint
struct Location tell_command;				// command for telemetry
struct Location next_command;				// command preloaded
long 	target_altitude;					// used for 
long 	offset_altitude;					// used for 
boolean	home_is_set	= false; 				// Flag for if we have gps lock and have set the home location


// IMU variables
// -------------
float G_Dt							= 0.02;		// Integration time for the gyros (DCM algorithm)
float COGX;								 		// Course overground X axis
float COGY							= 1; 		// Course overground Y axis


// Performance monitoring
// ----------------------
long 	perf_mon_timer;
//float 	imu_health; 							// Metric based on accel gain deweighting
int 	G_Dt_max;								// Max main loop cycle time in milliseconds
byte 	gyro_sat_count;
byte 	adc_constraints;
byte 	renorm_sqrt_count;
byte 	renorm_blowup_count;
int 	gps_fix_count;
byte	gcs_messages_sent;


// GCS
// ---
char GCS_buffer[53];
char display_PID = -1;					// Flag used by DebugTerminal to indicate that the next PID calculation with this index should be displayed

// System Timers
// --------------
unsigned long 	fast_loopTimer;				// Time in miliseconds of main control loop
unsigned long 	fast_loopTimeStamp;			// Time Stamp when fast loop was complete
int 			mainLoop_count;

unsigned long 	medium_loopTimer;			// Time in miliseconds of navigation control loop
byte 			medium_loopCounter;			// Counters for branching from main control loop to slower loops
byte 			medium_count;

byte 			slow_loopCounter;
byte 			superslow_loopCounter;

unsigned long 	deltaMiliSeconds; 			// Delta Time in miliseconds
unsigned long 	dTnav;						// Delta Time in milliseconds for navigation computations
unsigned long 	elapsedTime;				// for doing custom events
float 			load;						// % MCU cycles used

byte			FastLoopGate = 9;



// AC generic variables for future use
byte gled_status = HIGH;
long gled_timer;
int gled_speed = 200;

long cli_timer;
byte cli_status = LOW;
byte cli_step;

byte fled_status;
byte res1;
byte res2;
byte res3;
byte res4;
byte res5;
byte cam_mode;
byte cam1;
byte cam2;
byte cam3;

int ires1;
int ires2;
int ires3;
int ires4;

boolean SW_DIP1;  // closest to SW2 slider switch
boolean SW_DIP2;
boolean SW_DIP3;
boolean SW_DIP4;  // closest to header pins



// Basic Initialization
//---------------------
void setup() {
	init_ardupilot();

        #if ENABLE_EXTRAINIT
             init_extras();
        #endif

}

void loop()
{
	// We want this to execute at 100Hz 
	// --------------------------------
	if (millis() - fast_loopTimer > 9) {
		deltaMiliSeconds 	= millis() - fast_loopTimer;
		fast_loopTimer		= millis();
		load				= float(fast_loopTimeStamp - fast_loopTimer) / deltaMiliSeconds;
		G_Dt 				= (float)deltaMiliSeconds / 1000.f;		// used by DCM integrator
		mainLoop_count++;

		// Execute the fast loop
		// ---------------------
		fast_loop();
		fast_loopTimeStamp = millis();
	}
	
	if (millis() - medium_loopTimer > 19) {
		medium_loopTimer	= millis();
		medium_loop();
		
		/* commented out temporarily
		if (millis() - perf_mon_timer > 20000) {
			if (mainLoop_count != 0) {
				GCS.send_message(MSG_PERF_REPORT);
				if (log_bitmask & MASK_LOG_PM)
					Log_Write_Performance();
					
				resetPerfData();
			}
		}*/
	}
}

// Main loop 50-100Hz
void fast_loop()
{
	// IMU DCM Algorithm
	read_AHRS();

	// This is the fast loop - we want it to execute at 200Hz if possible
	// ------------------------------------------------------------------
	if (deltaMiliSeconds > G_Dt_max) 
		G_Dt_max = deltaMiliSeconds;
					
	// custom code/exceptions for flight modes
	// ---------------------------------------
	update_current_flight_mode();

	// write out the servo PWM values
	// ------------------------------
	set_servos_4();
}

void medium_loop()
{
	// Read radio
	// ----------
	read_radio();			// read the radio first

	// This is the start of the medium (10 Hz) loop pieces
	// -----------------------------------------
	switch(medium_loopCounter) {
	
		// This case deals with the GPS
		//-------------------------------
		case 0:
			medium_loopCounter++;
			update_GPS();
			readCommands();
			if(compass_enabled){
				compass.read();		 				// Read magnetometer
				compass.calculate(roll, pitch);		// Calculate heading
			}
 
			break;

		// This case performs some navigation computations
		//------------------------------------------------
		case 1:
			medium_loopCounter++;

			if(GPS.new_data){
				dTnav 				= millis() - medium_loopTimer;
				medium_loopTimer 	= millis();
			}
			
			// calculate the plane's desired bearing
			// -------------------------------------			
			navigate();
			break;

		// command processing
		//-------------------
		case 2:
			medium_loopCounter++;
			
			// Read Baro pressure
			// ------------------
			read_barometer();

			// altitude smoothing
			// ------------------
			calc_altitude_error();

			// perform next command
			// --------------------
			update_commands();
			break;

		// This case deals with sending high rate telemetry
		//-------------------------------------------------
		case 3:
			medium_loopCounter++;
						
			if (log_bitmask & MASK_LOG_ATTITUDE_MED && (log_bitmask & MASK_LOG_ATTITUDE_FAST == 0))
				Log_Write_Attitude((int)roll_sensor, (int)pitch_sensor, (int)yaw_sensor);

			if (log_bitmask & MASK_LOG_CTUN)
				Log_Write_Control_Tuning();

			if (log_bitmask & MASK_LOG_NTUN)
				Log_Write_Nav_Tuning();

			if (log_bitmask & MASK_LOG_GPS)
				Log_Write_GPS(GPS.time, current_loc.lat, current_loc.lng, GPS.altitude, current_loc.alt, (long) GPS.ground_speed, GPS.ground_course, GPS.fix, GPS.num_sats);

			send_message(MSG_ATTITUDE);		// Sends attitude data
			break;
			
		// This case controls the slow loop
		//---------------------------------
		case 4:
			
			// shall we trim the copter?
			// ------------------------
			read_trim_switch();
			
			// shall we check for engine start?
			// --------------------------------
			arm_motors();
			
			medium_loopCounter = 0;
			slow_loop();
			break;
			
		default:
			medium_loopCounter = 0;
			break;
	}
	
	// stuff that happens at 50 hz
	// ---------------------------
	
	// use Yaw to find our bearing error
	calc_bearing_error();
	
	// guess how close we are - fixed observer calc
	calc_distance_error();

		
	if (log_bitmask & MASK_LOG_ATTITUDE_FAST)
		Log_Write_Attitude((int)roll_sensor, (int)pitch_sensor, (int)yaw_sensor);

	if (log_bitmask & MASK_LOG_RAW)
		Log_Write_Raw();
		
	#if GCS_PROTOCOL == 6		// This is here for Benjamin Pelletier.	Please do not remove without checking with me.	Doug W
		readgcsinput();
	#endif
	
	#if ENABLE_HIL
		output_HIL();
	#endif

        #if ENABLE_CAM
                camera_stabilization();
        #endif

        #if ENABLE_AM
                flight_lights();
        #endif
        
        #if ENABLE_xx
                do_something_usefull();
        #endif              
	
	
	if (millis() - perf_mon_timer > 20000) {
		if (mainLoop_count != 0) {
			send_message(MSG_PERF_REPORT);
			if (log_bitmask & MASK_LOG_PM)
				Log_Write_Performance();
			resetPerfData();
		}
	}
}


void slow_loop()
{
	// This is the slow (3 1/3 Hz) loop pieces
	//----------------------------------------
	switch (slow_loopCounter){
		case 0:
			slow_loopCounter++;
			superslow_loopCounter++;
			if(superslow_loopCounter >=15) {
				// keep track of what page is in use in the log
				// *** We need to come up with a better scheme to handle this...
				eeprom_write_word((uint16_t *) EE_LAST_LOG_PAGE, DataFlash.GetWritePage());
				superslow_loopCounter = 0;
			}
			break;
			
		case 1:
			slow_loopCounter++;
			
			//Serial.println(stabilize_rate_roll_pitch,3);
			
			// Read 3-position switch on radio
			// -------------------------------
			read_control_switch();
			
			//Serial.print("I: ")
			//Serial.println(rc_1.get_integrator(), 1);
			
			
			// Read main battery voltage if hooked up - does not read the 5v from radio
			// ------------------------------------------------------------------------
			#if BATTERY_EVENT == 1
				read_battery();
			#endif
					
			break;
			
		case 2:
			slow_loopCounter = 0;
			update_events();
			break;

		default:
			slow_loopCounter = 0;
			break;

	}
}

void update_GPS(void)
{
	GPS.update();
	update_GPS_light();
	
	if (GPS.new_data && GPS.fix) {
		send_message(MSG_LOCATION);

		// for performance
		// ---------------
		gps_fix_count++;
		
		if(ground_start_count > 1){
			ground_start_count--;
		
		} else if (ground_start_count == 1) {
		
			// We countdown N number of good GPS fixes
			// so that the altitude is more accurate
			// -------------------------------------
			if (current_loc.lat == 0) {
				Serial.println("!! bad loc");
				ground_start_count = 5;
				
			} else {

				if (log_bitmask & MASK_LOG_CMD)
					Log_Write_Startup(TYPE_GROUNDSTART_MSG);
				
				init_home();
				// init altitude
				current_loc.alt = GPS.altitude;
				ground_start_count = 0;
			}
		}

		/* disabled for now
		// baro_offset is an integrator for the gps altitude error 
		baro_offset 	+= altitude_gain * (float)(GPS.altitude - current_loc.alt);
		*/
		
		current_loc.lng = GPS.longitude;	// Lon * 10 * *7
		current_loc.lat = GPS.latitude;		// Lat * 10 * *7
		
		COGX = cos(ToRad(GPS.ground_course / 100.0));
		COGY = sin(ToRad(GPS.ground_course / 100.0));
	}	
}
			
void update_current_flight_mode(void)
{
	if(control_mode == AUTO){
	//Serial.print("!");
		//crash_checker();				
		
		switch(command_must_ID){
			//case CMD_TAKEOFF:
			//	break;
	
			//case CMD_LAND:
			//	break;
				
			default:
				// Intput Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				calc_nav_pid();
				calc_nav_roll();
				calc_nav_pitch();
				
				// based on altitude error
				// -----------------------
				calc_nav_throttle();

				// Output Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// perform stabilzation
				output_stabilize();

				// hold yaw
				//output_yaw_hold();
				
				// apply throttle control
				output_auto_throttle();
				break;
		}
	
	}else{
	
		switch(control_mode){
				
			case STABILIZE:
				// Intput Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// clear any AP naviagtion values
				nav_pitch 		= 0;
				nav_roll 		= 0;
								
				// get desired yaw control from radio
				input_yaw_hold();
				
				// Output Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// apply throttle control
				output_manual_throttle();

				// hold yaw
				//output_yaw_hold();

				// perform stabilzation
				output_stabilize();
				break;

			case ALT_HOLD:
				// Intput Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// clear any AP naviagtion values
				nav_pitch 		= 0;
				nav_roll 		= 0;
				
				// get desired height from the throttle
				next_WP.alt 	= home.alt + (rc_3.control_in * 4) -100; // 0 - 1000 (40 meters)
				
				// get desired yaw control from radio
				input_yaw_hold();
				
				// based on altitude error
				// -----------------------
				calc_nav_throttle();
				
				
				// Output Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// apply throttle control
				output_auto_throttle();

				// hold yaw
				//output_yaw_hold();				

				// perform stabilzation
				output_stabilize();
				break;
				
			case RTL:
				// Intput Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				calc_nav_pid();
				calc_nav_roll();
				calc_nav_pitch();
				
				// based on altitude error
				// -----------------------
				calc_nav_throttle();

				// Output Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// apply throttle control
				output_auto_throttle();

				// hold yaw
				//output_yaw_hold();				

				// perform stabilzation
				output_stabilize();
				break;
				
			case POSITION_HOLD:
				// Intput Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				calc_nav_pid();
				calc_nav_roll();
				calc_nav_pitch();
								
				// get desired yaw control from radio
				input_yaw_hold();
				
				// based on altitude error
				// -----------------------
				calc_nav_throttle();
				
				
				// Output Pitch, Roll, Yaw and Throttle
				// ------------------------------------
				// apply throttle control
				output_auto_throttle();

				// hold yaw
				//output_yaw_hold();				

				// perform stabilzation
				output_stabilize();
				break;

			default:
				//Serial.print("$");
				break;
				
		}
	}
}

// called after a GPS read
void update_navigation()
{
	// wp_distance is in ACTUAL meters, not the *100 meters we get from the GPS
	// ------------------------------------------------------------------------

	// distance and bearing calcs only
	if(control_mode == AUTO){
		verify_must();
		verify_may();
	}else{

		switch(control_mode){				
			case RTL:
				update_crosstrack();
				break;							
		}
	}
}


void read_AHRS(void)
{
	// Perform IMU calculations and get attitude info
	//-----------------------------------------------------
	dcm.update_DCM(G_Dt);
	roll_sensor 	= dcm.roll_sensor;
	pitch_sensor 	= dcm.pitch_sensor;
	yaw_sensor 		= dcm.yaw_sensor;
}