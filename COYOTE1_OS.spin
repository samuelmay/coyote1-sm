''=======================================================================  
'' TITLE: COYOTE1_OS.SPIN
''
'' DESCRIPTION:
''    Operating System module for the Coyote-1 audio effects pedal.
''
'' COPYRIGHT:
''   Copyright (C)2008,2009 Eric Moyer
''
'' LICENSING:
''   This file is part of the Coyote-1 O/S
''   The Coyote-1 O/S is free software: you can redistribute it and/or modify
''   it under the terms of the GNU General Public License as published by
''   the Free Software Foundation, either version 3 of the License, or
''   (at your option) any later version.
''   
''   The Coyote-1 O/S is distributed in the hope that it will be useful,
''   but WITHOUT ANY WARRANTY; without even the implied warranty of
''   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''   GNU General Public License for more details.
''   
''   You should have received a copy of the GNU General Public License
''   along with The Coyote-1 O/S.  If not, see <http://www.gnu.org/licenses/>.                                                          
''   
''======================================================================= 
''
''  REVISION HISTORY:
''
''  Rev       Date      Description
''  -------   --------  ---------------------------------------------------
''  1.00.00   07-19-08  Initial Release.
''  1.00.02   08-06-08  Initial Shipping configuration
''  2.00.00   10-19-08  Add manufacturing diagnostics
''  2.01.00   11-01-08  Add scrolling version display
''                      Update 'Gain' system resource so it's range is 0-100% (as displayed) instead of 0-200% (as it was previously behaving)
''                      Add temporary workaround for the clkfreq/tube distorion bug posted at http://www.openstomp.com/phpbb/viewtopic.php?f=4&t=19
''  2.01.01   02-24-09  Correct knob value display algorithm (was misbehaving for control sockets with very small data ranges)
''  2.01.02   05-20-09  Fix incorrect reference to TICKS_PER_MICROFRAME from spin code (should have been to HW#TICKS_PER_MICROFRAME). 
''
''=======================================================================

CON

  _clkmode = xtal2 + pll8x            ' enable external clock and pll times 8
  _xinfreq = 10_000_000 + 0000        ' set frequency to 10 MHZ plus some error for xtals that are not exact add 1000-5000 usually works
  _stack = (64 >> 2)

  '------------------------------------
  'User modes
  '------------------------------------
  USER_MODE__PATCH_INFO      = 0
  USER_MODE__PATCH_SELECT    = 1
  USER_MODE__PARAMETER_EDIT  = 2
  USER_MODE__VERSION_SCROLL  = 3

  '------------------------------------
  'Patch status
  '------------------------------------
  PATCH_STATUS__IDLE         = 0     'The status before a patch load has been attempted (ideally, should never
                                     '  be deisplayed to the user).
  PATCH_STATUS__RUNNING      = 1     'The currently selected patch is running
  PATCH_STATUS__DNE          = 2     'The currently selected patch does not exist (EEPROM slot empty)
  PATCH_STATUS__FAILED       = 3     'The patch load failed (patch error of some kind (bad data, missing module, etc.))
  PATCH_STATUS__INTNL_ERR    = 4     'An internal error occurred (EEPROM read fail, etc.)
  
  '------------------------------------
  'Miscellaneous
  '------------------------------------
  END_OF_LIST                = $ff   'Used to mark the end of data lists

  '------------------------------------
  'Button debouncing
  '------------------------------------
  BUTTON_DEBOUNCE_TICKS      = 10
  BUTTON0_FLAG               = $01
  BUTTON1_FLAG               = $02

  '------------------------------------
  'Button debouncing
  '------------------------------------
  KNOB_CHANGE_DISPLAY_TICKS      = 200   'Used to time the duration for which a changed knob's value is displayed
  KNOB_CHANGE_DISPLAY_SENSITIVTY = 100   'Sensitivity of knob change display threshold (granularity is essentially = (1/sensitivity) * knob full rotation angle)

  '------------------------------------
  'Error Display
  '------------------------------------
  ERROR_DISPLAY_TICKS            =  400  'Used to time the duration for which an error is displayed
  CLIPPING_DISPLAY_TICKS         =  100  'Used to time the duration for which an output clipping indication is displayed
  OVERRUN_DISPLAY_TICKS          =  100  'Used to time the duration for which a microframe overrun indication is displayed   
  
  '------------------------------------
  'Events
  '------------------------------------
  EVENT_BUTTON0_DOWN         = $01    ' Button 0 down event 
  EVENT_BUTTON1_DOWN         = $02    ' Button 1 down event
  EVENT_BUTTON01_DOWN        = $04    ' Button 0 and 1 simultaneous down event
  EVENT_BUTTON01_LONG_HOLD   = $08    ' Button 0 and 1 held for a long time event

  '------------------------------------
  'Append flags
  '------------------------------------
  APPEND__NORMAL             = $00    ' Normal append operation
  APPEND__NO_SPACES          = $01    ' Causes the string append function to ignore any spaces in the appended string


VAR

  '------------------------------------
  'SYSTEM_STATE block
  '------------------------------------
  long  ss__frame_counter
  long  ss__out_right
  long  ss__out_left
  long  ss__in_right
  long  ss__in_left
  long  ss__knob_pos_virtual[hw#NUM_KNOBS]
  long  ss__knob_position[hw#NUM_KNOBS]
  long  ss__knob_calibration[hw#NUM_KNOBS]
  long  ss__knob_measurement[hw#NUM_KNOBS]
  long  ss__knob_prev_meas[hw#NUM_KNOBS]
  long  ss__flags
  long  ss__debug_pass
  long  ss__capture_state
  long  ss__capture_sample_interval
  long  ss__num_static_modules
  long  ss__static_module_descriptor_p[hw#MAX_STATIC_MODULES]
  long  ss__shuttle_buffer_p
  long  ss__rpc_control
  long  ss__led0_socket
  long  ss__led1_socket
  long  ss__button0_socket
  long  ss__button0_toggle_socket
  long  ss__button1_socket
  long  ss__button1_toggle_socket
  long  ss__patch_number
  long  ss__module_mask
  long  ss__patch_mask
  long  ss__clipping_detect
  long  ss__overrun_detect
  long  ss__gain_in_socket
  long  ss__gain_out_socket
  long  ss__gain_control_socket
  long  ss__display_buffer[hw#LCD_CHARS / hw#BYTES_PER_LONGWORD]   
  long  ss__patch_name [hw#PATCH_NAME_CHARS / hw#BYTES_PER_LONGWORD]
  long  ss__capture_samples[hw#NUM_CAPTURE_SAMPLES]
  long  ss__unused
  
  byte  shadow_GPIO0                        ' Shadow copy of GPIO0 register in PLD

  '=========================================
  ' Global Longs
  '=========================================
  
  '------------------------------------
  '512 Longword scratchpad for module load / conduit engine build / etc
  '------------------------------------
  long  cogram_image[512]

  '------------------------------------
  '512 Longword scratchpad for module descriptors
  '------------------------------------
  long  module_descriptor_image[512]

  '------------------------------------
  '512 Longword buffer for processing patch binary / module descriptors / etc
  '------------------------------------
  long  shuttle_buffer[hw#SHUTTLE_BUFFER_SIZE_LW]

  '------------------------------------
  'Module Control Blocks
  '  One for each possible executing module in a patch.
  '  Used to pass each module a pointer to the SYSTEM_STATE block, and to exchange socket data
  '------------------------------------
  long  module_control_blocks[hw#MAX_ACTIVE_MODULES * hw#MCB_SIZE_LONGWORDS]

  '------------------------------------
  'RAM Pool
  '  Pool of RAM available for effect modules 
  '------------------------------------
  long  ram_pool[hw#RAM_POOL_SIZE_LONGWORDS]

  'Button debouncing and event detection
  long  g_buttons_stable_timer
  long  g_buttons_current_state
  long  g_buttons_previous_state
  long  g_buttons_prev_stable_state

  long  g_tenative_patch_number
  long  g_button_init_socket[hw#NUM_BUTTONS]

  'Knob position change display managment
  long  g_knob_position_prev[hw#NUM_KNOBS]
  long  g_knob_change_timer

  'Error detection/display  
  long  g_error_display_timer
  long  g_clipping_timer
  long  g_overrun_timer
  
  'Active module data
  long  num_active_modules
  long  active_module_signature[hw#MAX_ACTIVE_MODULES]

  'Knob value display
  long  g_knob_range_low[hw#NUM_KNOBS]
  long  g_knob_range_high[hw#NUM_KNOBS]
  long  g_knob_flags[hw#NUM_KNOBS] 
  long  g_knob_name[(hw#KNOB_NAME_CHARS / hw#BYTES_PER_LONGWORD) * hw#NUM_KNOBS]
  long  g_knob_units[(hw#KNOB_UNITS_CHARS / hw#BYTES_PER_LONGWORD) * hw#NUM_KNOBS]

  'Heap size tracking for heap allocation
  long  g_heap_available

  'RAM pool size tracking for RAM allocation
  long  g_ram_pool_available

  'Knob read
  long  g_knob_read_current_knob

  'The version string (holds the scrolling version text)
  byte  g_version_string[hw#VERSION_STRING_SIZE]
  byte  g_version_scroll_state
  byte  g_version_scroll_position
  long  g_version_scroll_timer 

  '=========================================
  ' Global Bytes
  '=========================================
  
  byte  active_module_cogid[hw#MAX_ACTIVE_MODULES]
     

  byte  user_mode
  byte  conduit_engine_cogid

  long  debug_source_p
  long  debug_dest_p
  long  debug_dummy_target

  byte  g_knob_change_id

  'Error detection/display
  byte  g_error_code
  byte  g_error_display_code
  byte  g_patch_status          ' The status of the currently selected patch (running/failed/does net exist, etc.)

  byte  g_events                ' Bitfield of event masks

  byte  g_tenative_patch_name[hw#PATCH_NAME_CHARS]
  byte  g_knob_is_sticky[hw#NUM_KNOBS] 
 
'=======================================================================
'OBJECTS SECTION 
'======================================================================= 
OBJ

   statics        : "COYOTE1_static_module_list"    'Any static MODULES are linked in using this object
   hw             : "COYOTE1_HW_Definitions.spin"   'Hardware definitions
   serial         : "COYOTE1_Serial_Comm.spin"      'Combo Serial Communications and LCD driver
   conduit_engine : "COYOTE1_Conduit_Engine.spin"   'Conduit engine
   i2c            : "COYOTE1_I2C_Driver.spin"
   
'=======================================================================
'PUBLIC FUNCTION SECTION
'======================================================================= 
PUB start | i, j

  'Initialize I/O pins
  OUTA := hw#OUTA_INIT 
  DIRA := hw#DIRA_INIT

  'Initialze SYSTEM_STATE block
  repeat i from 0 to hw#SS_OFFSET__LAST_ENTRY step 4
    long[@ss__frame_counter + i] :=0

  '------------------------------------                                                                                                            
  'Initialze the Serial driver
  '------------------------------------
  'Disable the LCD driver which is part of the serial driver.  The LCD will be controlled..
  '..manually until boot has proceeded farther.
  ss__flags |= hw#FLAG__LCD_DISABLE    
  serial.Start(@ss__frame_counter)
  serial.TX_diagnostic_string(string("B00"))
  
  'Clear display buffer
  LCD_Clear

  'Set SYSTEM STATE flags
  ss__flags |= hw#FLAG__LCD_BACKLIGHT

  'Set mode
  user_mode := USER_MODE__PATCH_INFO
  ss__patch_number := 0
  g_patch_status := PATCH_STATUS__IDLE

  '------------------------------------                                                                                                            
  'Initialze static MODULE descriptor table
  '------------------------------------
  ss__num_static_modules := 0
  repeat i from 0 to hw#MAX_STATIC_MODULES - 1
    j := statics.get_static_module_desc_p(i)
    if(j <> 0)
      ss__static_module_descriptor_p[ss__num_static_modules] := j 
      ++ss__num_static_modules


  'Initialize pointer to shuttle buffer
  ss__shuttle_buffer_p := @shuttle_buffer

  'Intialize RPC command
  ss__rpc_control  := hw#RPC_CMD__NONE

  'Initialize led states
  ss__led0_socket := 0
  ss__led1_socket := 0

  'Initialize number of currently active modules
  num_active_modules := 0

  'Initialize cogids
  repeat i from 0 to constant(hw#MAX_ACTIVE_MODULES - 1)
    active_module_cogid[i] := hw#NO_COG 
  conduit_engine_cogid := hw#NO_COG

  'Initialize button debouncing
  g_buttons_stable_timer := BUTTON_DEBOUNCE_TICKS + 1
  g_buttons_current_state := 0
  g_buttons_previous_state := 0
  g_buttons_prev_stable_state := 0
  ss__button0_toggle_socket := 0
  ss__button1_toggle_socket := 0

  'Initialize events
  g_events := 0

  'Initialize knob managment
  g_knob_change_timer := 0
  g_knob_change_id := 0

  'Initialize error display
  g_error_display_timer := 0
  g_error_code := hw#ERR__SUCCESS
  g_error_display_code := hw#ERR__SUCCESS

  'Initialize clipping detection
  ss__clipping_detect := 0
  g_clipping_timer := 0
  g_overrun_timer := 0

  'Initialize knob ranges and associated text
  InitializeKnobDisplayData

  'Initialize sticky knobs
  repeat i from 0 to constant(hw#NUM_KNOBS - 1)
    g_knob_is_sticky[i] := 0
  
  '------------------------------------
  'Initialze LCD
  '------------------------------------
  serial.TX_diagnostic_string(string("B20")) 

  repeat until not lockset(hw#LOCK_ID__MEMBUS)
  
  'Enable the LCD control pins
  LCD_enable_LCD_mux
  
  'Initialize the LCD
  LCD_send_command(hw#LCD_CMD__SET_DISPLAY_OPT)
  LCD_send_command(hw#LCD_CMD__LCD_ON)
  LCD_send_command(hw#LCD_CMD__CLEAR_DISPLAY)
  LCD_send_command(hw#LCD_CMD__MODE_SET)

  'Load custom LCD character graphics
  LCD_send_command(hw#LCD_CMD__HOME_CGRAM)
  i := @custom_lcd_chars
  repeat while byte[i] <> END_OF_LIST
    LCD_send_data (byte[i])
    ++i
  lockclr(hw#LOCK_ID__MEMBUS) 

  '------------------------------------
  'Show O/S build
  '------------------------------------
  serial.TX_diagnostic_string(string("B30"))
  repeat until not lockset(hw#LOCK_ID__MEMBUS)
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+2), string(  "Coyote-1 O/S"   ))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+5), string(    "v2.01.02"     ))
  Update_LCD 
  'Disable LCD mux so that the pin can be controlled by other cogs
  PLD_enable_PLD_mux
  lockclr(hw#LOCK_ID__MEMBUS)  
  waitcnt(cnt+120000000)         
  
  '------------------------------------
  'Calibrate Knobs
  '------------------------------------
  serial.TX_diagnostic_string(string("B40"))
  'repeat i from 0 to 3 
  read_knobs(hw#KNOB_OPERATION__CALIBRATE)
     
  '------------------------------------
  'Initialze CODEC
  '------------------------------------
  serial.TX_diagnostic_string(string("B50")) 
  MEMBUS_write(hw#CCR_INIT, hw#MEMBUS_CNTL__SET_CCR)

  '------------------------------------
  'Enable the LCD driver in the Serial Engine
  '------------------------------------
  serial.TX_diagnostic_string(string("B60")) 
  'Clear display buffer first.  Serial driver will take over LCD display.    
  LCD_Clear
  Update_LCD
  ss__flags &= !hw#FLAG__LCD_DISABLE  

  '------------------------------------
  'Start CODEC Engine
  '------------------------------------
  serial.TX_diagnostic_string(string("B70")) 
  cognew(@_CODEC_engine_entry, @ss__frame_counter)

  '------------------------------------
  'Check for power-on operations
  '------------------------------------
  serial.TX_diagnostic_string(string("B80")) 
  OUTA &= !(hw#PIN__BUTTON_MUX)   'Set the hardware mux so that button 0 can be read
  if(INA & hw#PIN__BUTTON_READ) <> 0
    'Button 0 is being held during power-on
    serial.TX_diagnostic_string(string("B81"))
    
    'Set the button 0 flag (the button debouncing code has not had a chance to execute yet, and it will take several calls
    '..to ReadButtons() before the button press event is detected there).       
    ss__flags |=  hw#FLAG__BUTTON_0
                                                                 'xxxxxxxxxxxxxxxx  LCD field width (16 characters) 
    LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+1), string( "Format EEPROM?"   ))
    LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("No           Yes" ))

    'Wait for button 0 release
    repeat while (ss__flags &  hw#FLAG__BUTTON_0 ) <> 0
      ReadButtons

    j := false
    repeat while(not j)
      ReadButtons
      if (ss__flags &  hw#FLAG__BUTTON_0 ) <> 0
        'BUTTON 0 PRESSED (Cancel Erase)
        j := true 'Done

      if (ss__flags &  hw#FLAG__BUTTON_1 ) <> 0
        'BUTTON 1 PRESSED (Format EEPROM)
        FormatEeprom   
        LCD_Clear
                                                                     'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
        LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Format Complete"   )) 
        waitcnt(cnt+120000000)
        j :=  true 'Done

  
  
  serial.TX_diagnostic_string(string("B82")) 
  OUTA |= hw#PIN__BUTTON_MUX   'Set the hardware mux so that button 1 can be read
  if(INA & hw#PIN__BUTTON_READ) <> 0 
  
    'Button 1 is being held during power-on
    serial.TX_diagnostic_string(string("B83"))
    
    'Set the button 1 flag (the button debouncing code has not had a chance to execute yet, and it will take several calls
    '..to ReadButtons() before the button press event is detected there).       
    ss__flags |=  hw#FLAG__BUTTON_1
                                                                 'xxxxxxxxxxxxxxxx  LCD field width (16 characters) 
    LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Run Diagnostics?"))
    LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("No           Yes" ))

    'Wait for button 1 release
    repeat while (ss__flags &  hw#FLAG__BUTTON_1 ) <> 0
      ReadButtons

    j := false
    repeat while(not j)
      ReadButtons
      if (ss__flags &  hw#FLAG__BUTTON_0 ) <> 0
        'BUTTON 0 PRESSED (Cancel Diagostics)
        j := true 'Done

      if (ss__flags &  hw#FLAG__BUTTON_1 ) <> 0
        'BUTTON 1 PRESSED (Run Diagnostics)
        RunDiagnostics 'Never returns
        
  '------------------------------------
  'Start Test GUI
  '------------------------------------
  'test_gui.start (@ss__frame_counter)
  
  'Start the main OS loop (never returns)
  serial.TX_diagnostic_string(string("B90")) 
  OS_main_loop
 
'=======================================================================
'PRIVATE FUNCTION SECTION
'======================================================================= 
PRI OS_main_loop | i, j, k, rpc_data0
'' The main Operating System processing loop

  'Fetch the list (bitmask) of occupied module slots in EEPROM
  i2c.ReadWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__MODULE_MASK), @ss__module_mask)
  'Fetch the list (bitmask) of occupied patch slots in EEPROM 
  i2c.ReadWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__PATCH_MASK), @ss__patch_mask)

  'Start the current patch
  g_error_code := load_and_run_patch
      
  repeat

    'Enable LCD backlight
    ss__flags |= hw#FLAG__LCD_BACKLIGHT   

    '---------------------------------
    ' Process errors
    '---------------------------------
    'If an error has occurred
    if (g_error_code <> hw#ERR__SUCCESS)
       'A new error has occurred.  Reset the timer so that it is displayed.
       g_error_display_timer := ERROR_DISPLAY_TICKS
       g_error_display_code  := g_error_code
    'Clear the error
    g_error_code := hw#ERR__SUCCESS
    
    '------------------------------------
    'Process Serial Communications
    '------------------------------------
    serial.Process_RX  

    '------------------------------------
    'Read Buttons
    '------------------------------------
    ReadButtons

    '------------------------------------
    'Read Knobs
    '------------------------------------
    read_knobs(hw#KNOB_OPERATION__READ)

    repeat i from 0 to constant(hw#NUM_KNOBS-1)
      'Remember previous knob positions  
      if ((ss__knob_position[i] /  CONSTANT(hw#CONTROL_SOCKET_MAX_VALUE/KNOB_CHANGE_DISPLAY_SENSITIVTY)) <> g_knob_position_prev[i])
        g_knob_change_timer := KNOB_CHANGE_DISPLAY_TICKS
        g_knob_change_id := i
      g_knob_position_prev[i] := ss__knob_position[i] /  CONSTANT(hw#CONTROL_SOCKET_MAX_VALUE/KNOB_CHANGE_DISPLAY_SENSITIVTY)    

     'Manage sticky knobs
      if(g_knob_is_sticky[i] <> 0)
        'The knob is sticky.  Check whether it is time to unstick it.
        'NOTE: The math is done shifted right one bit so that the margin check at the high end of the knob range does not break down due 
        '      to a summation result which exceeds the max supported positive integer in spin.
        if(((ss__knob_position[i]>>1) > (ss__knob_pos_virtual[i]>>1) - constant(hw#KNOB_STICKYNESS_MARGIN>>1)) and ((ss__knob_position[i]>>1) < (ss__knob_pos_virtual[i]>>1) + constant(hw#KNOB_STICKYNESS_MARGIN>>1)))
          'Knob physical position matches knob virtual position.  Unstick the knob.
          g_knob_is_sticky[i] := 0
      else
        'The knob is not sticky. Copy the real position to the virtual position
        ss__knob_pos_virtual[i] := ss__knob_position[i] 

    
    '------------------------------------
    'Copy LED socket state to LED flags
    '------------------------------------
    if (ss__led0_socket < $40000000)
      ss__flags &= !hw#FLAG__LED_0  'LED0 off  
    else
      ss__flags |=  hw#FLAG__LED_0  'LED0 on        
      
      
    if (ss__led1_socket < $40000000)
      ss__flags &= !hw#FLAG__LED_1  'LED1 off
    else
      ss__flags |=  hw#FLAG__LED_1  'LED1 on
    
    '------------------------------------
    'Show output clipping and overrun indicators
    '------------------------------------

    'Detect CLIPPING
    if(ss__clipping_detect <> 0)
      g_clipping_timer := CLIPPING_DISPLAY_TICKS
      'Clear the clipping detector (set in the CODEC engine)
      ss__clipping_detect := 0

    'Detect OVERRUN  
    if(ss__overrun_detect <> 0)
      g_overrun_timer := OVERRUN_DISPLAY_TICKS
      'Clear the overrun detector (set by effect modules when an overrun is self detected)
      ss__overrun_detect := 0

    'Display CLIPPING/OVERRUN indications and update display timers
    if (g_clipping_timer <> 0)
      --g_clipping_timer 
      if( g_overrun_timer <> 0)
        'CLIPPING & OVERRUN   
        --g_overrun_timer
        byte[@ss__display_buffer + 15] := hw#ASCII_CUSTOM__CLIP_AND_OVERRUN
      else
        'CLIPPING
        byte[@ss__display_buffer + 15] := hw#ASCII_CUSTOM__CLIP
    else
      if( g_overrun_timer <> 0)
        'OVERRUN   
        --g_overrun_timer
        byte[@ss__display_buffer + 15] := hw#ASCII_CUSTOM__OVERRUN
      else
        'No clipping or overrun
        byte[@ss__display_buffer + 15] := hw#ASCII_space
 
    if (g_error_display_timer <> 0)
      '------------------------------------
      'Error display
      '------------------------------------
      'An error has occurred and needs to be displayed to the user
      LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+8), string("       "))
      LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2), string("                "))
      LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1), string("Error:"))
      Int_To_3Digit_String(@string_3digit_0, g_error_display_code)  
      LCD_print_string (hw#LCD_POS__HOME_LINE1+6, @string_3digit_0 + 1)
      --g_error_display_timer
      'Keep decrementing knob change display timer, if active  
      if(g_knob_change_timer <> 0)
        --g_knob_change_timer    
       
    elseif (g_knob_change_timer <> 0)
      '------------------------------------
      'Knob position display
      '------------------------------------
      DisplayKnobSetting
      --g_knob_change_timer
      ' Abort version scroll whenver knob change display is envoked
      if(user_mode == USER_MODE__VERSION_SCROLL)
        user_mode := USER_MODE__PATCH_INFO
        g_version_scroll_timer := 0 

    else
      '------------------------------------
      'Regular operating mode diplay
      '------------------------------------
      case user_mode
       
        '----------------------------------------------------------------------------------------------
        ' MODE: PATCH INFO
        '----------------------------------------------------------------------------------------------
        USER_MODE__PATCH_INFO:   
          'Display patch number
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1), string("Patch:"))
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+8), string("       ")) 
          if(ss__patch_number == hw#PATCH_NUMBER_NONE )
            ' Host loaded patch
            LCD_print_string (hw#LCD_POS__HOME_LINE1+6, string("--")) 
          else
            'Numbered patch
            Int_To_3Digit_String(@string_3digit_0, ss__patch_number)  
            LCD_print_string (hw#LCD_POS__HOME_LINE1+6, @string_3digit_0 + 1)
       
          'Display patch name       
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2), @ss__patch_name)
       
          'EVENT: Button 0 & 1 down
          if((g_events & EVENT_BUTTON01_DOWN) <> 0)
            '-------------------------------
            ' Enter PATCH SELECT state
            '-------------------------------
            'Go to "Patch Select" mode
            user_mode := USER_MODE__PATCH_SELECT
            'Remember what patch was selected when "Patch Select" mode was entered
            g_tenative_patch_number := ss__patch_number
            GetTenativePatchName
          else
            '-------------------------------
            ' Enter VERSION SCROLL state
            '-------------------------------
            ++g_version_scroll_timer
            if(g_version_scroll_timer > hw#SCROLL__WAIT_TICKS)
              user_mode := USER_MODE__VERSION_SCROLL
              g_version_scroll_timer := 0
              g_version_scroll_position := 0
              'Copy LCD top line to scroll string, so that the scroll transition is uniform
              repeat i from 0 to CONSTANT(hw#LCD_LINE_WIDTH - 1)
                g_version_string[i] := byte[@ss__display_buffer + i]
            
        '----------------------------------------------------------------------------------------------
        ' MODE: PATCH SELECT
        '----------------------------------------------------------------------------------------------
        USER_MODE__PATCH_SELECT:   
          'Display patch number
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1), string("Patch:"))
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+8), @string_left_arrow_0)
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+11), string("     ")) 
          if(g_tenative_patch_number == hw#PATCH_NUMBER_NONE )
            'Host loaded patch
            LCD_print_string (hw#LCD_POS__HOME_LINE1+6, string("--")) 
          else
            'Numbered patch
            Int_To_3Digit_String(@string_3digit_0, g_tenative_patch_number)  
            LCD_print_string (hw#LCD_POS__HOME_LINE1+6, @string_3digit_0 + 1)
       
          'Display patch name       
          LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2), @g_tenative_patch_name)
          
          'EVENT: Button 0 down
          if((g_events & EVENT_BUTTON0_DOWN) <> 0)
            'Decrement patch number
            DecrementTenativePatch
       
          'EVENT: Button 1 down
          if((g_events & EVENT_BUTTON1_DOWN) <> 0)
            'Increment patch number
            IncrementTenativePatch
       
          'EVENT: Button 0 & 1 down
          if((g_events & EVENT_BUTTON01_DOWN) <> 0)
            '------------------------------
            ' Adopt the new patch
            '------------------------------
            'If the selected patch changed
            if(g_tenative_patch_number <>  ss__patch_number)
              'Load the new patch
              LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1), string("Loading...     "))
              ss__patch_number := g_tenative_patch_number
              g_error_code := load_and_run_patch
            
            'Go to "Patch Info" mode   
            user_mode := USER_MODE__PATCH_INFO 
          
        '----------------------------------------------------------------------------------------------
        ' MODE: VERSION SCROLL
        '----------------------------------------------------------------------------------------------
        USER_MODE__VERSION_SCROLL:

          ++g_version_scroll_timer
          if(g_version_scroll_timer > hw#SCROLL__SCROLL_CHAR_TICKS)
            g_version_scroll_timer := 0
            j := g_version_scroll_position
            if(g_version_string[j] == 0)
              ' End of sroll cycle reached
              user_mode := USER_MODE__PATCH_INFO
              g_version_scroll_timer := 0   

            else
              ' Display the scrolling version string
              repeat i from 0 to CONSTANT(hw#LCD_LINE_WIDTH - 1)
                byte[@ss__display_buffer + i] := g_version_string[j]
                ++j
                ' If end of version string reached
                if (g_version_string[j] == 0)
                  ' display fromm beginning of string
                  j := 0
              ++g_version_scroll_position 
            
          'EVENT: Button 0 & 1 down
          if((g_events & EVENT_BUTTON01_DOWN) <> 0)
            '-------------------------------
            ' Enter PATCH SELECT state
            '-------------------------------
            'Go to "Patch Select" mode
            user_mode := USER_MODE__PATCH_SELECT
            'Remember what patch was selected when "Patch Select" mode was entered
            g_tenative_patch_number := ss__patch_number
            GetTenativePatchName
      
    '------------------------------------
    'Process RPC (Remote Procedure Call) requests from the attached host PC (i.e. the OpenStomp Workbench application)
    '------------------------------------
    if(((ss__rpc_control & hw#RPC_FLAG__EXECUTE_REQUEST) <> 0) and ((ss__rpc_control & hw#RPC_FLAG__EXECUTE_ACK) == 0))

      'Get RPC data 0 field (auxiliary supporting data for command)
      rpc_data0 := ((ss__rpc_control & hw#RPC_DATA0_MASK)>>hw#RPC_DATA0_SHIFT)   

      'Process RPC command
      case (ss__rpc_control & hw#RPC_CMD__MASK)

        '----------------------------------------------------------------------------------------------
        ' RPC: Patch Run
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__PATCH_RUN:
          'Start the patch
          g_error_code := start_patch

          if (g_error_code == hw#ERR__SUCCESS)
          
            'Set the patch number
            ss__patch_number := hw#PATCH_NUMBER_NONE 'Indicate that this was a host-loaded patch
           
            'Switch to patch display mode
            user_mode := USER_MODE__PATCH_INFO

        '----------------------------------------------------------------------------------------------
        ' RPC: Format EEPROM
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__FORMAT_EEPROM:
          g_error_code := FormatEeprom

        '----------------------------------------------------------------------------------------------
        ' RPC: Module Fetch
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MODULE_FETCH:
          'Clear the shuttle buffer
          bytefill(@shuttle_buffer, 0, hw#SHUTTLE_BUFFER_SIZE_LW)
          
          'data0 field contains the module index
          if( rpc_data0 < hw#MAX_STATIC_MODULES )
             'Index points to a static module (in RAM)
             if (rpc_data0 => ss__num_static_modules)
               'Static module does not exist
               g_error_code := hw#ERR__INDEXED_MODULE_DNE
             else
               'Get the module code size
               k := long[ss__static_module_descriptor_p[rpc_data0] + hw#MDES_OFFSET__CODE_SIZE]
               'Copy the module code to the shuttle buffer
               bytemove( @shuttle_buffer, long[ss__static_module_descriptor_p[rpc_data0] + hw#MDES_OFFSET__CODE_P], k)

          else
             'Index points to a dynamic module (in EEPROM)

             'Determine the Module Descriptor address in EEPROM (place in j)
             j:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((rpc_data0 - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
             'Read the module code length from the module descriptor in EEPROM  (place in k)
             i2c.ReadLong(hw#I2C_ADDR__BOOT_EEPROM, j + hw#MDES_OFFSET__CODE_SIZE, @k)
             'Determine the Module Code address in EEPROM (place in j)
             j:= hw#EEPROM_OFFSET__MODULES + ((rpc_data0 - hw#MAX_STATIC_MODULES) * hw#MODULE_SIZE)       
             'Read the module code from EEPROM into the shuttle buffer
             g_error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, j, k, @shuttle_buffer)

        '----------------------------------------------------------------------------------------------
        ' RPC: Module Store
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MODULE_STORE:
          'data0 field contains the module index
          if( rpc_data0 < hw#MAX_STATIC_MODULES )
            'Index points to a static module (in RAM)
            g_error_code := hw#ERR__ILLEGAL_MODULE_INDEX

          else
             'Index points to a dynamic module (in EEPROM)

             'Determine the target address in EEPROM 
             j:= hw#EEPROM_OFFSET__MODULES + ((rpc_data0 - hw#MAX_STATIC_MODULES) * hw#MODULE_SIZE)
             'Write the data to EEPROM
             g_error_code := i2c.WriteBlock(hw#I2C_ADDR__BOOT_EEPROM, j, hw#MODULE_SIZE, @shuttle_buffer)

        '----------------------------------------------------------------------------------------------
        ' RPC: Patch Store
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__PATCH_STORE:
          'data0 field contains the patch index
          if( rpc_data0 < hw#MAX_PATCHES )
            'Index points to a valid patch location (in EEPROM)
             
            'Determine the patch address in EEPROM 
            j:= hw#EEPROM_OFFSET__PATCHES + (rpc_data0 * hw#PATCH_SIZE)
            'Write the data to EEPROM
            g_error_code := i2c.WriteBlock(hw#I2C_ADDR__BOOT_EEPROM, j, hw#PATCH_SIZE, @shuttle_buffer)
            'If an error occurred
            if (g_error_code == hw#ERR__SUCCESS)
              'Set the corresponding bit in the patch mask in the CCB to indicate that the targeted
              'EEPROM patch slot contains valid data
              ss__patch_mask |= (1 << rpc_data0)
              g_error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__PATCH_MASK), ss__patch_mask)

        '----------------------------------------------------------------------------------------------
        ' RPC: Patch Fetch
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__PATCH_FETCH:
          'data0 field contains the patch index
          if( rpc_data0 < hw#MAX_PATCHES )
            'Index points to a valid patch location (in EEPROM)

            'Read the patch into the shuttle buffer
            g_error_code := patch_to_shuttle_buffer(rpc_data0)

               
        '----------------------------------------------------------------------------------------------
        ' RPC: Module Descriptor Fetch
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MODULE_DESC_FETCH:
          'Clear the shuttle buffer
          bytefill(@shuttle_buffer, 0, hw#SHUTTLE_BUFFER_SIZE_LW)
          
          'data0 field contains the module index
          if( rpc_data0 < hw#MAX_STATIC_MODULES )
             'Index points to a static module (in RAM)
             if (rpc_data0 => ss__num_static_modules)
               'Static module does not exist
               g_error_code := hw#ERR__INDEXED_MODULE_DNE
             else
               'Get the module descriptor size
               k := long[ss__static_module_descriptor_p[rpc_data0] + hw#MDES_OFFSET__SIZE]
               'Copy the module descriptor to the shuttle buffer
               bytemove( @shuttle_buffer, ss__static_module_descriptor_p[rpc_data0], k)

          else
             'Index points to a dynamic module (in EEPROM)

             'Determine the Module Descriptor address in EEPROM 
             j:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((rpc_data0 - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
             'Read the module descriptor length from the module descriptor in EEPROM
             i2c.ReadLong(hw#I2C_ADDR__BOOT_EEPROM, j + hw#MDES_OFFSET__SIZE, @k)
             'Read the data from EEPROM
             g_error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, j, k, @shuttle_buffer)
                  
        '----------------------------------------------------------------------------------------------
        ' RPC: Module Descriptor Store
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MODULE_DESC_STORE:
          'data0 field contains the module index
          if( rpc_data0 < hw#MAX_STATIC_MODULES )
            'Index points to a static module (in RAM)
            g_error_code := hw#ERR__ILLEGAL_MODULE_INDEX

          else
            'Index points to a dynamic module (in EEPROM)
             
            'Determine the target address in EEPROM 
            j:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((rpc_data0 - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
            'Write the data to EEPROM
            g_error_code := i2c.WriteBlock(hw#I2C_ADDR__BOOT_EEPROM, j, hw#MODULE_DESCRIPTOR_SIZE, @shuttle_buffer)
            'If write was successful
            if (g_error_code == hw#ERR__SUCCESS)
              'Set the corresponding bit in the module mask in the CCB to indicate that the targeted
              'EEPROM module slot contains valid data
              ss__module_mask |= (1 << (rpc_data0 - hw#MAX_STATIC_MODULES))
              g_error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__MODULE_MASK), ss__module_mask)
            
        '----------------------------------------------------------------------------------------------
        ' RPC: Module Delete
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MODULE_DELETE:
          'data0 field contains the module index
          if( rpc_data0 < hw#MAX_STATIC_MODULES )
            'Index points to a static module (in RAM)
            g_error_code := hw#ERR__ILLEGAL_MODULE_INDEX

          else
             'Index points to a dynamic module (in EEPROM)

            'Clear the corresponding bit in the module mask in the CCB to indicate that the targeted
            'EEPROM module slot contains valid data
            ss__module_mask &= !(1 << (rpc_data0 - hw#MAX_STATIC_MODULES))
            g_error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__MODULE_MASK), ss__module_mask)

        '----------------------------------------------------------------------------------------------
        ' RPC: Patch Delete
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__PATCH_DELETE:
          'data0 field contains the patch index
          if( rpc_data0 => hw#MAX_PATCHES )
            g_error_code := hw#ERR__ILLEGAL_PATCH_INDEX

          else
             'Index points to a valid patch number (in EEPROM)

            'Clear the corresponding bit in the patch mask in the CCB to indicate that the targeted
            'EEPROM patch slot contains valid data
            ss__patch_mask &= !(1 << rpc_data0)
            g_error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__PATCH_MASK), ss__patch_mask)

        '----------------------------------------------------------------------------------------------
        ' RPC: Get Patch Info
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__GET_PATCH_INFO:
          'Copy the names of all patches to the shuttle buffer.  

          'Get a pointer to the shuttle buffer
          j := @shuttle_buffer 

          repeat i from 0 to constant(hw#MAX_PATCHES - 1)
            'If the patch exists
            if ((ss__patch_mask & (1 << i)) <> 0)
               'Patch exists.  Copy the patch name.
               
               'Determine the Patch address in EEPROM 
                k := hw#EEPROM_OFFSET__PATCHES + (i * hw#PATCH_SIZE)
                
                'Read the data from EEPROM 
                g_error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, k + hw#PBIN_OFFSET__PATCH_NAME, hw#PATCH_NAME_CHARS, j)
                j += hw#PATCH_NAME_CHARS 

            else
               'Patch does not exist.  Report a blank name
               repeat k from 0 to constant(hw#PATCH_NAME_CHARS - 1)
                 byte[j] := 0
                 ++j
        '----------------------------------------------------------------------------------------------
        ' RPC: Fetch Module Control Blocks (MCBs)
        '----------------------------------------------------------------------------------------------
        hw#RPC_CMD__MCB_FETCH:
          'Clear the shuttle buffer
          bytefill(@shuttle_buffer, 0, hw#SHUTTLE_BUFFER_SIZE_LW)
          'Copy the MCBs
          bytemove(@shuttle_buffer, @module_control_blocks, hw#MAX_ACTIVE_MODULES * hw#MCB_SIZE_LONGWORDS)

      'Acknowledge execution of the RPC
      ss__rpc_control |= hw#RPC_FLAG__EXECUTE_ACK
 
          
PRI DecrementTenativePatch
'' Decrements the tenative patch number during user patch selection.  The selection will
'' not be commited and become the active patch until selected by the user.
  if((g_tenative_patch_number == hw#PATCH_NUMBER_NONE) or (g_tenative_patch_number == 0))
    g_tenative_patch_number := hw#MAX_PATCHES - 1
  else
    --g_tenative_patch_number
  GetTenativePatchName

PRI IncrementTenativePatch
'' Increments the tenative patch number during user patch selection.  The selection will
'' not be commited and become the active patch until selected by the user.
  if((g_tenative_patch_number == hw#PATCH_NUMBER_NONE) or (g_tenative_patch_number == hw#MAX_PATCHES - 1))
    g_tenative_patch_number := 0
  else
    ++g_tenative_patch_number
  GetTenativePatchName

PRI GetTenativePatchName | patch_addr
'' Retrieves the tenative patch number during user patch selection.  The selection will
'' not be commited and become the active patch until selected by the user.
  if (g_tenative_patch_number == hw#PATCH_NUMBER_NONE)
    'The only way for this to be true is when first entering patch select mode while running a downloaded patch, so
    'adopy the current patch name
    bytemove(@g_tenative_patch_name, @ss__patch_name, hw#PATCH_NAME_CHARS)
    
  elseif(( (1 << g_tenative_patch_number) & ss__patch_mask) == 0)
    'The patch does not exist
     bytefill(@g_tenative_patch_name, 20, hw#PATCH_NAME_CHARS)
     bytemove(@g_tenative_patch_name,string("<None>"), 6)
     
  else
    'Fetch the patch name from EEPROM

    'Determine the Patch address in EEPROM 
    patch_addr := hw#EEPROM_OFFSET__PATCHES + (g_tenative_patch_number * hw#PATCH_SIZE)
                
    'Read the data from EEPROM 
    i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, patch_addr + hw#PBIN_OFFSET__PATCH_NAME, hw#PATCH_NAME_CHARS, @g_tenative_patch_name)
    

PRI load_and_run_patch | error_code, i

  error_code := hw#ERR__SUCCESS

  '--------------------------------------
  ' Initialize the version string
  '--------------------------------------

  ' Clear the version string.  Leave first 16 characters free to hold LCD top line contents (for clear scroll transition).
  ' The first 16 characters will be loaded later, when the "Patch:xx        " display text is generated.
  repeat i from 0 to CONSTANT(hw#LCD_LINE_WIDTH - 1)
    g_version_string[i] := hw#ASCII_space
  g_version_string[hw#LCD_LINE_WIDTH] := 0

  ' Intitialize version string display handling
  g_version_scroll_state := hw#SCROLL_STATE__WAIT   
  g_version_scroll_position := 0
  g_version_scroll_timer := 0   

  '--------------------------------------
  ' Load patch
  '--------------------------------------
  
  'If the current patch exists in EEPROM
  if(( ss__patch_mask & (1 << ss__patch_number)) <> 0)
    'Copy the patch to the shuttle buffer
    error_code := patch_to_shuttle_buffer(ss__patch_number)
    if (error_code == hw#ERR__SUCCESS)    
      'Start the patch
      error_code := start_patch
      if (error_code == hw#ERR__SUCCESS)
        g_patch_status := PATCH_STATUS__RUNNING
      else
        g_patch_status := PATCH_STATUS__FAILED
        bytemove(@ss__patch_name,string("<Patch Failed>  "), hw#PATCH_NAME_CHARS) 
    else
      'An internal error occurred during the patch copy
      g_patch_status := PATCH_STATUS__INTNL_ERR
      
  else
    'The patch does not exist
    g_patch_status := PATCH_STATUS__DNE
    bytefill(@ss__patch_name, 20, hw#PATCH_NAME_CHARS)
    bytemove(@ss__patch_name,string("<None>"), 6) 
    
  return (error_code)  

PRI patch_to_shuttle_buffer(patch_id) | patch_eeprom_address, error_code

  'Determine the patch address in EEPROM 
  patch_eeprom_address:= hw#EEPROM_OFFSET__PATCHES + (patch_id * hw#PATCH_SIZE)      

  'Read the data from EEPROM 
  error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, patch_eeprom_address, hw#PATCH_SIZE, @shuttle_buffer)
  
  return (error_code)
  
PRI start_patch | mem_p, i, j, source_module_index, dest_module_index, socket_index, source_socket_p, dest_socket_p, start_p, code_p, data_lw_addr, jump_opcode, module_signature, error_code

  error_code := hw#ERR__SUCCESS 'Default to successful completion
  
  '--------------------------
  'Stop the conduit engine (if running) and any currently executing modules (if running)
  '--------------------------

  'Halt the frame counter, so that any executing modules will stop cleanly (i.e. not in the middle of a..
  '..MEMBUS access or something.)
  ss__flags |= hw#FLAG__RESET_FRAME_COUNTER
  waitcnt(cnt+constant(HW#TICKS_PER_MICROFRAME*3))  
  
  if(conduit_engine_cogid <> hw#NO_COG)
    cogstop(conduit_engine_cogid)
    
  repeat i from 0 to constant(hw#MAX_ACTIVE_MODULES - 1)
    if(active_module_cogid[i] <> hw#NO_COG)
      cogstop(active_module_cogid[i])
      
  num_active_modules := 0

  'Restart the frame counter
  ss__flags &= !(hw#FLAG__RESET_FRAME_COUNTER )

  '--------------------------
  'Append patch version the version string
  '--------------------------

  ' Add the text "Patch RRR.RRR.RRR, " where "RRR.RRR.RRR" is the patch revision
  AppendString (@g_version_string, string("Patch"), 100, APPEND__NORMAL)
  AppendVersion(@shuttle_buffer + hw#PBIN_OFFSET__PATCH_VERSION)
  
  '--------------------------
  'Process patch name
  '-------------------------- 
  mem_p := @shuttle_buffer + hw#PBIN_OFFSET__PATCH_NAME
  repeat i from 0 to (CONSTANT(hw#PATCH_NAME_CHARS - 1))
    byte[@ss__patch_name + i] := byte[mem_p + i]

  '--------------------------
  'Process system resources
  '-------------------------- 
  'Jump over system resource locations
  mem_p := @shuttle_buffer + hw#PBIN_OFFSET__SYS_RESOURCES
  repeat while (long[mem_p] <> hw#PBIN_END_OF_RESOURCE_LIST)
    mem_p += 4

  'Advance to efect signatures
  mem_p += 4

  'Initialize the the available heap space.  start_module() will decrement it accordingly as modules are started.
  g_heap_available     := hw#SRAM_SIZE
  g_ram_pool_available := hw#RAM_POOL_SIZE_BYTES
  
  '--------------------------
  'Process modules
  '--------------------------
  repeat while (long[mem_p] <> hw#PBIN_END_OF_EFFECT_LIST)
  
    module_signature := long[mem_p]
    
    'Attempt to locate and start the module 
    error_code := start_module(module_signature)
    
    'If the module could not be located/started
    if(error_code <> hw#ERR__SUCCESS)
      'Return error
      return (error_code)
      
    'Skip graphical location and name  
    mem_p += constant(4 + 4 + 16) 

  'Advance to conduits
  mem_p += 4
  
  '--------------------------
  'Process conduits
  '--------------------------
  ' Note:  Code in this section dymanically builds the conduit engine in assembly. 
  '         All assembly constuctor code is commented with ">>>"
  '--------------------------

  '>>> Copy the beginning part of the conduit engine
  repeat i from  0 to (conduit_engine.get_splice_address - conduit_engine.get_start_address) step 4
    long[@cogram_image + i] :=  long[conduit_engine.get_start_address + i]

  '>>> Initialize code generation variables
  start_p      := @cogram_image                         ' Start of code, in RAM
  code_p       := @cogram_image + (conduit_engine.get_splice_address - conduit_engine.get_start_address)
                                                        ' Splice point (new code insertion), in RAM
  data_lw_addr := $100                                  ' Data storage point, in COG ram (i.e. longword address)

  '>>> Save the jump command 
  jump_opcode  := long[code_p]

  'Reinitialize the knob display parameters
  InitializeKnobDisplayData

  'Loop through conduits
  repeat while (long[mem_p] <> hw#PBIN_END_OF_CONDUIT_LIST)

    'Determine source socket 
    source_module_index := byte[mem_p]
    ++mem_p
    socket_index := byte[mem_p]
    ++mem_p
    source_socket_p := get_socket_p(source_module_index, socket_index)

    'Determine dest socket
    dest_module_index := byte[mem_p]
    ++mem_p
    socket_index := byte[mem_p]
    ++mem_p
    dest_socket_p := get_socket_p(dest_module_index, socket_index)

    'If the source module was a knob
    if ((source_module_index => hw#SYS_MODULE__KNOB0) and (source_module_index =< hw#SYS_MODULE__KNOB3))
      'Determine the knob
      i := source_module_index - hw#SYS_MODULE__KNOB0

      'If the knob is connected to a module
      if (dest_module_index =< hw#MAX_ACTIVE_MODULES)
         
        'Determine the module index (place in j)
        error_code := FindModuleBySignature(active_module_signature[dest_module_index], @j)
        if (error_code <> hw#ERR__SUCCESS)
          return(error_code)
        else
          'Bind the knob min/max/name/units
          error_code := BindKnobParameters(i, j, socket_index)
          if (error_code <> hw#ERR__SUCCESS)
            return(error_code)
      else
        BindKnobToSysresource(i, dest_module_index)

    '>>> Generate socket copy code
    long[code_p] := constant($A0BC0000 | (conduit_engine#LW_ADDRESS__r1 << 9 )) | data_lw_addr   ' mov  r1, <source socket address>
    long[start_p + (data_lw_addr << 2)] := source_socket_p
    code_p += 4
    data_lw_addr += 1
     
    long[code_p] := constant($08BC0000 | ( conduit_engine#LW_ADDRESS__r2 << 9 ) | conduit_engine#LW_ADDRESS__r1)           ' rdlong r2, r1
    code_p += 4 
     
    long[code_p] := constant($A0BC0000 | ( conduit_engine#LW_ADDRESS__r1 << 9 )) | data_lw_addr   ' mov  r1, <dest socket address>
    long[start_p + (data_lw_addr << 2)] := dest_socket_p
    code_p += 4
    data_lw_addr += 1

    long[code_p] := constant($083C0000 | ( conduit_engine#LW_ADDRESS__r2 << 9 ) | conduit_engine#LW_ADDRESS__r1)           ' wrlong r2, r1
    code_p += 4 
    
    'Skip graphical drawing information
    mem_p += 4

  '>>> Terminate the main copy loop with the jump back to the frame sync code
  long[code_p] := jump_opcode                                            ' jmp #frame_sync
  
  '>>> Start the conduit engine
  conduit_engine_cogid := cognew(@cogram_image, @ss__frame_counter)
  if(conduit_engine_cogid == hw#NO_COG)
    return(hw#ERR__CONDUIT_ENG_START_FAILED)
  
  'Advance to static Assignments
  mem_p += 4

  
  '--------------------------
  'Process assignments
  '--------------------------
  'Loop through assignments
  repeat while (long[mem_p] <> hw#PBIN_END_OF_ASSIGNMENT_LIST)
  
    'Determine dest socket
    dest_module_index := byte[mem_p]
    ++mem_p
    socket_index := byte[mem_p]
    ++mem_p
    dest_socket_p := get_socket_p(dest_module_index, socket_index)

    'Skip two unused bytes
    mem_p += 2

    'Get the assignment value
    j := long[mem_p]
    mem_p += 4
    
    'Make the assignment
    long[ dest_socket_p ] := j

  '--------------------------
  'Load buttons with their initialization values
  '--------------------------
  ss__button0_toggle_socket := g_button_init_socket[0]
  ss__button1_toggle_socket := g_button_init_socket[1]

  '--------------------------
  'Load knobs with their initialization values
  '--------------------------
  ' Note: Each knobs init socket and output socker are mapped to the same memory location
  '       (ss_knob_pos_virtuan[n]).  The location is set when assignments are processed
  '       above, and then the "sticky" flag is set below.  Once the sticky flag has
  '       been cleared (by rotating the knob to match the virtual postition) then the
  '       sticky flag is cleared and from then on the actual knob position is always
  '       copied to the virtual position.
   
  'Initialize sticky knobs
  repeat i from 0 to constant(hw#NUM_KNOBS - 1)
    g_knob_is_sticky[i] := 1   
  
  'Return successful completion
  return(error_code)  

PRI start_module(signature) | i, j, k, module_descriptor_p, module_code_p, mcb_p, active_module_index, heap_requirement, ram_requirement, module_index, error_code

  '-------------------------
  'Check that there are not already the max number of allowable modules running      
  '-------------------------
  if(num_active_modules => hw#MAX_ACTIVE_MODULES)
    return(hw#ERR__MAX_ACTIVE_MOD_EXCEEDED)

  '-------------------------
  'Locate the requested module by signature 
  '-------------------------
  error_code := FindModuleBySignature(signature, @module_index)
  if(error_code <> hw#ERR__SUCCESS)
    return(error_code)

  '-------------------------
  'Fetch the module from EEPROM if necessary
  '-------------------------
  if (module_index < hw#MAX_STATIC_MODULES)
    '-------------------------
    'Static Module
    '-------------------------

    'Get pointer to module descriptor
    module_descriptor_p := ss__static_module_descriptor_p[module_index]
    'Get pointer to module code 
    module_code_p := long[module_descriptor_p + hw#MDES_OFFSET__CODE_P]
      
  else
    '-------------------------
    'Dynamic Module
    '-------------------------
    'Copy the module code and module descriptor from EEPROM to local RAM
    
    'Get EEPROM address of module descirptor (place in j) 
    j:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((module_index - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
    'Read the module descriptor length from the module descriptor in EEPROM (place in k)
    i2c.ReadLong(hw#I2C_ADDR__BOOT_EEPROM, j + hw#MDES_OFFSET__SIZE, @k)
    'Read the module descriprtor from EEPROM
    g_error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, j, k, @module_descriptor_image)
    'Set pointer to the module desroptor
    module_descriptor_p := @module_descriptor_image

    'Get EEPROM address of module code (place in j) 
    j:= hw#EEPROM_OFFSET__MODULES + ((module_index - hw#MAX_STATIC_MODULES) * hw#MODULE_SIZE)  
    'Read the module code length from the module descriptor copy in RAM (place in k)
    k := long[module_descriptor_p  + hw#MDES_OFFSET__CODE_SIZE]   
    'Read the module code from EEPROM into a local RAM copy
    g_error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, j, k, @cogram_image)
    'Set pointer to the module code
    module_code_p := @cogram_image

  '-------------------------
  'Adopt the new module
  '-------------------------
  active_module_index := num_active_modules
  ++num_active_modules 
  active_module_signature[active_module_index] := signature

  '--------------------------
  'Add the module name and rev to the versioin string
  '--------------------------

  ' Add the text "NNNNNNNNNNNNNNNN vRRR.RR.RR, " where "NNN..." is the module name, and "RRR.RR.RR" is the module revision
  j := GetModuleNamePointer(module_descriptor_p)
  AppendString (@g_version_string, j, hw#MODULE_NAME_CHARS, APPEND__NORMAL)
  AppendVersion (module_descriptor_p + hw#MDES_OFFSET__REVISION)
  
  '-------------------------  
  'Initialize the associated module control block
  '-------------------------
  'Get a pointer to the module control block  
  mcb_p := @module_control_blocks + ((active_module_index) * constant(hw#MCB_SIZE_LONGWORDS << 2))
   
  'Initialize pointer to the SYSTEM_STATE block
  long[mcb_p + hw#MCB_OFFSET__SS_BLOCK_P] := @ss__frame_counter
   
  'Clear the socket exchange area
  repeat j from hw#MCB_OFFSET__SOCKET_EXCHANGE to hw#MSB_OFFSET__LAST_SOCKET_EXC_LW step 4
    long[mcb_p  + j] := 0
   
  'Allocate heap (SRAM)
  heap_requirement := long[module_descriptor_p  + hw#MDES_OFFSET__HEAP_REQ]  
  if( g_heap_available < heap_requirement )
    return(hw#ERR__OUT_OF_SRAM)
  long[mcb_p + hw#MCB_OFFSET__HEAP_BASE_P] := hw#SRAM_SIZE - g_heap_available     'Set base offset (in SRAM) of the module's allocated heap region
  g_heap_available -= heap_requirement                                            'Decrement the remaining heap avalable
   
  'Allocate RAM pool
  ram_requirement := long[module_descriptor_p  + hw#MDES_OFFSET__RAM_REQ]                                    
  if(g_ram_pool_available < ram_requirement)                                      
    return(hw#ERR__OUT_OF_RAM_POOL)
  long[mcb_p + hw#MCB_OFFSET__RAM_BASE_P] := @ram_pool + (hw#RAM_POOL_SIZE_BYTES - g_ram_pool_available)  'Set base offset (in RAM) of the module's allocated heap region     
  g_ram_pool_available -= ram_requirement                                                                 'Decrement the remaining RAM pool avalable    
   
  ' Load socket default values
  '(not yet implemented; all are zero for now from the initialization above)
   
  '-------------------------  
  'Start the module
  '-------------------------  
  active_module_cogid[active_module_index] := cognew(module_code_p, mcb_p)
  if(active_module_cogid[active_module_index] == hw#NO_COG)
    return(hw#ERR__MODULE_COG_START_FAILED)
   
  'Module loaded successfully
  return(hw#ERR__SUCCESS)


PRI FindModuleBySignature(signature, module_index_p) | module_index, module_descriptor_p, mdes_address, mdes_signature

  'Check static modules
  repeat module_index from 0 to (ss__num_static_modules - 1)
    module_descriptor_p := ss__static_module_descriptor_p[module_index]
      if((long[module_descriptor_p + hw#MDES_OFFSET__SIGNATURE]) == signature)
        'Module found
        long[module_index_p] := module_index
        return(hw#ERR__SUCCESS)

  'Check dynamic modules
  repeat module_index from hw#MAX_STATIC_MODULES to constant(hw#MAX_STATIC_MODULES + hw#MAX_DYNMAIC_MODULES - 1)
    'If module is valid
    if (((1 << (module_index - hw#MAX_STATIC_MODULES)) & ss__module_mask) <> 0)
      'Determine the Module Descriptor address in EEPROM 
      mdes_address:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((module_index - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
      'Read the module descriptor signature from the module descriptor in EEPROM
      i2c.ReadLong(hw#I2C_ADDR__BOOT_EEPROM, mdes_address + hw#MDES_OFFSET__SIGNATURE, @mdes_signature)
      if(mdes_signature == signature)
        'Module found
        long[module_index_p] := module_index
        return(hw#ERR__SUCCESS)

  return(hw#ERR__MODULE_NOT_FOUND)
   
PRI get_socket_p (module_index, socket_index) | socket_p, mcb_p

    'Point the socket somewhere safe in case the code below does not resolve a proper pointer
    socket_p := @debug_dummy_target

    if (module_index =< hw#MAX_ACTIVE_MODULES)
      'Get a pointer to the appropriate module control block  
      mcb_p := @module_control_blocks + (module_index * constant(hw#MCB_SIZE_LONGWORDS << 2))
      'Get a pointer to the appropriate socket within the MCB
      socket_p := mcb_p + hw#MCB_OFFSET__SOCKET_EXCHANGE + (socket_index << 2)

    else

      'Module index represents an internal system resource
      case module_index
        hw#SYS_MODULE__AUDIO_IN_L:
          socket_p := @ss__in_left
          
        hw#SYS_MODULE__AUDIO_IN_R:
          socket_p := @ss__in_right
        
        hw#SYS_MODULE__AUDIO_OUT_L:
          socket_p := @ss__out_left
        
        hw#SYS_MODULE__AUDIO_OUT_R:
          socket_p := @ss__out_right 

        hw#SYS_MODULE__KNOB0:
          'NOTE: Knob socket 0 (the position) and 1 (the init socket) both get mapped
          '      to the same memory location. 
          socket_p := @ss__knob_pos_virtual[0]
       
        hw#SYS_MODULE__KNOB1:
          'NOTE: Knob socket 0 (the position) and 1 (the init socket) both get mapped
          '      to the same memory location. 
          socket_p := @ss__knob_pos_virtual[1]
       
        hw#SYS_MODULE__KNOB2:
          'NOTE: Knob socket 0 (the position) and 1 (the init socket) both get mapped
          '      to the same memory location. 
          socket_p := @ss__knob_pos_virtual[2]
       
        hw#SYS_MODULE__KNOB3:
          'NOTE: Knob socket 0 (the position) and 1 (the init socket) both get mapped
          '      to the same memory location. 
          socket_p := @ss__knob_pos_virtual[3]

        hw#SYS_MODULE__BUTTON0:
          if (socket_index == 0)
            socket_p := @ss__button0_toggle_socket   
          elseif (socket_index == 1)   
            socket_p := @ss__button0_socket
          else
            socket_p := @g_button_init_socket[0]      

        hw#SYS_MODULE__BUTTON1:  
          if (socket_index == 0)
            socket_p := @ss__button1_toggle_socket   
          elseif (socket_index == 1)   
            socket_p := @ss__button1_socket
          else
            socket_p := @g_button_init_socket[1]

        hw#SYS_MODULE__LED0:
          socket_p := @ss__led0_socket
       
        hw#SYS_MODULE__LED1:
          socket_p := @ss__led1_socket

        hw#SYS_MODULE__GAIN:
          if (socket_index == 0)
            socket_p := @ss__gain_in_socket   
          elseif (socket_index == 1)   
            socket_p := @ss__gain_out_socket
          else
            socket_p := @ss__gain_control_socket

    return socket_p

PRI ReadButtons

    'Get the current button states
    OUTA &= !(hw#PIN__BUTTON_MUX)   'Set the hardware mux so that button 0 can be read
    g_buttons_current_state := 0
    if(INA & hw#PIN__BUTTON_READ) <> 0
      'Button 0 is down  
      g_buttons_current_state |= BUTTON0_FLAG
    OUTA |= hw#PIN__BUTTON_MUX      'Set the hardware mux so that button 1 can be read    
    if(INA & hw#PIN__BUTTON_READ) <> 0
      'Button 1 is down  
      g_buttons_current_state |= BUTTON1_FLAG 
    OUTA &= !(hw#PIN__BUTTON_MUX)   'Return button mux to normal position

    'Increment timer if buttons are stable
    if (g_buttons_current_state == g_buttons_previous_state)
      ++g_buttons_stable_timer
    else
      g_buttons_stable_timer := 0

    'Remember state for next pass
    g_buttons_previous_state := g_buttons_current_state

    'Clear event flags
    g_events := 0
    
    'If buttons have been stable long enough for debouncing, then interpret the stable state vs. the previous stable
    'state to detect events.
    if(g_buttons_stable_timer == BUTTON_DEBOUNCE_TICKS)
    
      'If Button 0 Down event
      if (((g_buttons_prev_stable_state & BUTTON0_FLAG )== 0) and  ((g_buttons_current_state & BUTTON0_FLAG )<> 0))
        g_events |= EVENT_BUTTON0_DOWN
        if (user_mode <> USER_MODE__PATCH_SELECT)
          ss__flags |=  hw#FLAG__BUTTON_0
          ss__button0_socket := hw#CONTROL_SOCKET_MAX_VALUE
          'Toggle the toggle socket value
          if(ss__button0_toggle_socket => $40000000)
            ss__button0_toggle_socket := 0
          else
            ss__button0_toggle_socket := hw#CONTROL_SOCKET_MAX_VALUE

      'If Button 0 Up event
      if (((g_buttons_prev_stable_state & BUTTON0_FLAG )<> 0) and  ((g_buttons_current_state & BUTTON0_FLAG )== 0))
        if (user_mode <> USER_MODE__PATCH_SELECT)  
          ss__flags &= !hw#FLAG__BUTTON_0 
          ss__button0_socket := 0 

      'If Button 1 Down event
      if (((g_buttons_prev_stable_state & BUTTON1_FLAG )== 0) and  ((g_buttons_current_state & BUTTON1_FLAG )<> 0))
        g_events |= EVENT_BUTTON1_DOWN 
        if (user_mode <> USER_MODE__PATCH_SELECT)  
          ss__flags |=  hw#FLAG__BUTTON_1
          ss__button1_socket := hw#CONTROL_SOCKET_MAX_VALUE
          'Toggle the toggle socket value
          if(ss__button1_toggle_socket => $40000000)
            ss__button1_toggle_socket := 0
          else
            ss__button1_toggle_socket := hw#CONTROL_SOCKET_MAX_VALUE

      'If Button 1 Up event
      if (((g_buttons_prev_stable_state & BUTTON1_FLAG )<> 0) and  ((g_buttons_current_state & BUTTON1_FLAG )== 0))
        if (user_mode <> USER_MODE__PATCH_SELECT)
          ss__flags &= !hw#FLAG__BUTTON_1 
          ss__button1_socket := 0

      'If Button 0 and Button 1 simultaneous press event
      if (((g_buttons_prev_stable_state & constant(BUTTON1_FLAG | BUTTON0_FLAG))== 0) and  ((g_buttons_current_state & constant(BUTTON1_FLAG | BUTTON0_FLAG) )== constant(BUTTON1_FLAG | BUTTON0_FLAG)))
        g_events |= EVENT_BUTTON01_DOWN   
      

      'Remember this as the previous stable state
      g_buttons_prev_stable_state := g_buttons_current_state
      
PRI read_knobs(knob_operation)| knob_position, delta, knob_inc_direction_flag, knob_measurement
  
  'Initialize the frequency "adder" used for phase accumulation for counter A.
  FRQA := 1

  OUTA |= hw#PIN__KNOB_STROBE
  if knob_operation == hw#KNOB_OPERATION__CALIBRATE
    ' Give capacitors a change to charge
    waitcnt(cnt + 400000)
  

  repeat g_knob_read_current_knob from 0 to CONSTANT(hw#NUM_KNOBS - 1)   

    'Drain all knob capacitors
    DIRA |= (hw#PIN__KNOB_0 << g_knob_read_current_knob)    
    waitcnt(cnt + 20000)
   
    'Start counter A.  The conunter is configured to count the number of clock cycles for which the
    'accumulated voltage on the associated knob capacitor is LOW.
    CTRA := (hw#CTR_KNOB_SENSE_CONFIG & $FFFFFFF0) | (7 + g_knob_read_current_knob) 'NOTE: i selects PINA, which is the physical KNOB sense pin
     
     
    'Clear the phase accumulator (i.e. the cap "off" timer)
    PHSA := 0
     
    'Strobe the knob, and shunt the knob potentiometer so that that cap and 1K resistor can be
    'measured independantly of the current knob position.
    if knob_operation == hw#KNOB_OPERATION__CALIBRATE
      OUTA |= hw#PIN__KNOB_SHUNT
     
    'Release knob capacitor, allowing it to charge
    DIRA &= !(hw#PIN__KNOB_0 << g_knob_read_current_knob)
     
    'Wait for the knob cap to charge
    repeat while (INA[hw#PINNUMBER__KNOB_0 + g_knob_read_current_knob] == 0)
     
    'Stop the counter
    CTRA := 0

    'Deassert the strobes
    OUTA &= !hw#PIN__KNOB_SHUNT
     
    if knob_operation == hw#KNOB_OPERATION__CALIBRATE  
      'Store the calibration referece time.  This is the expeted time (in processor clock cycles) for the
      'assicated knob capacitor to charge if the knob were in the full CCW (i.e. zero ohm) position.  The
      'expeted charge time in the full CW position (i.e. 10K ohms) is 11 x the calibration reference.
      ss__knob_calibration[g_knob_read_current_knob] := PHSA - 500 
    else 
      'Store the measured knob time.
      knob_measurement := PHSA
     
      '------------------------------------
      'Use hysterisis to remove knob jitter  
      '------------------------------------
      delta := knob_measurement - ss__knob_prev_meas[g_knob_read_current_knob]
     
      knob_inc_direction_flag := hw#FLAG__KNOB_0_INC << g_knob_read_current_knob
      if ss__flags & knob_inc_direction_flag
        'Knob is increasing
        if delta =< -hw#KNOB_MEASUREMENT_JITTER
          'Moved downward more than jitter
          'Change direction to decreasing
          ss__flags &= !knob_inc_direction_flag
          
          ss__knob_measurement[g_knob_read_current_knob] := knob_measurement
            
        else
          if delta > 1
            'Moved upward
            ss__knob_measurement[g_knob_read_current_knob] := knob_measurement
      else
         'Knob is decreasing
        if delta => hw#KNOB_MEASUREMENT_JITTER
          'Moved upward more than jitter
          'Change direction to increasing
          ss__flags |= knob_inc_direction_flag
          ss__knob_measurement[g_knob_read_current_knob] := knob_measurement
            
        else
          if delta < 1
            'Moved downward
            ss__knob_measurement[g_knob_read_current_knob] := knob_measurement     
           
      'Remember previous measurement
      ss__knob_prev_meas[g_knob_read_current_knob] := ss__knob_measurement[g_knob_read_current_knob]       
     
      '------------------------------------
      'Calculate the knob position  
      '------------------------------------
      if ss__knob_measurement[g_knob_read_current_knob] < ss__knob_calibration[g_knob_read_current_knob]
        ss__knob_measurement[g_knob_read_current_knob] := ss__knob_calibration[g_knob_read_current_knob]
      'NOTE: The number below ($15000) was experimentally found to provide a good range of usable angle for the knobs, with
      '      a small "dead band" of margin above the 100% position.  Increasing the constant will increase the amound of dead
      '      band.  If you find that your knobs to not reach 100% at their full clockwise position, then decreasing the constant
      '      will fix that.
      knob_position := ($15000 * (ss__knob_measurement[g_knob_read_current_knob] - ss__knob_calibration[g_knob_read_current_knob]) ) / ( ss__knob_calibration[g_knob_read_current_knob] * 2) 
      if knob_position  => $10000
        ss__knob_position[g_knob_read_current_knob] := hw#CONTROL_SOCKET_MAX_VALUE
      else
        ss__knob_position[g_knob_read_current_knob] := knob_position <<= 15 
     
PRI InitializeKnobDisplayData | i
  bytefill(@g_knob_name, 0, constant(hw#KNOB_NAME_CHARS * hw#NUM_KNOBS))
  bytefill(@g_knob_units, 0, constant(hw#KNOB_UNITS_CHARS * hw#NUM_KNOBS))
  repeat i from 0 to constant(hw#NUM_KNOBS - 1)
    g_knob_range_low[i] := 0
    g_knob_range_high[i] := 100
    g_knob_flags[i] := 0
    bytemove(@g_knob_name + (i * hw#KNOB_NAME_CHARS), string("<Unassigned>"),12)
    bytemove(@g_knob_units + (i * hw#KNOB_UNITS_CHARS), string("%"),1)          

PRI DisplayKnobSetting | text_p, done, i, length

  'A knob change recently.  Display its value.

  '----------------------------------------
  'Display knob number
  '----------------------------------------  
  'Print "K<n>:" where <n> is the knob number
  byte[@ss__display_buffer] := hw#ASCII_K
  byte[@ss__display_buffer + 1] := hw#ASCII_0 + g_knob_change_id
  byte[@ss__display_buffer + 2] := hw#ASCII_colon

  '----------------------------------------
  'Display knob name (with trailing blanks)
  '---------------------------------------- 
  text_p :=  @g_knob_name + ( g_knob_change_id * hw#KNOB_NAME_CHARS )
  done := false 
  repeat i from 3 to constant(hw#LCD_POS__END_LINE1 - 1)
    if (not done)
      if (byte[text_p] <> 0)
        byte[@ss__display_buffer + i] := byte[text_p]
        ++text_p 
      else
        done := true
    if done
       byte[@ss__display_buffer + i] := hw#ASCII_space

  '----------------------------------------
  'Display knob value 
  '----------------------------------------
  'Determine the max length of the number to be displayed by rendering the max value
  length :=  Int_To_10Digit_String(@string_10digit_0, g_knob_range_high[g_knob_change_id])
  'Translate the knob value (which is between 0 and CONTROL_SOCKET_MAX_VALUE) into a value in the specified range (low to high)
  i := (ss__knob_pos_virtual[g_knob_change_id] / (hw#CONTROL_SOCKET_MAX_VALUE/(g_knob_range_high[g_knob_change_id] - g_knob_range_low[g_knob_change_id] + 1))) + g_knob_range_low[g_knob_change_id]
  if(i > g_knob_range_high[g_knob_change_id])
    i := g_knob_range_high[g_knob_change_id]
  'Print value into a 10 digit string   
  Int_To_10Digit_String(@string_10digit_0, i)
  'Only print enough digits to fit the length of the maximum value  
  LCD_print_string (hw#LCD_POS__HOME_LINE2, @string_10digit_0 + (10 - length))
  'Display blank space after value
  byte[@ss__display_buffer + hw#LCD_POS__HOME_LINE2 + length] := hw#ASCII_space
  
  '----------------------------------------
  'Display knob units (with trailing blanks) 
  '----------------------------------------
  text_p :=  @g_knob_units + ( g_knob_change_id * hw#KNOB_UNITS_CHARS )
  done := false 
  repeat i from (hw#LCD_POS__HOME_LINE2 + length + 1) to hw#LCD_POS__END_LINE2
    if (not done)
      if (byte[text_p] <> 0)
        byte[@ss__display_buffer + i] := byte[text_p]
        ++text_p 
      else
        done := true
    if done
       byte[@ss__display_buffer + i] := hw#ASCII_space

PRI BindKnobParameters(knob_number, dest_module_index, socket_index) |  error_code, j, k
  error_code := hw#ERR__SUCCESS
  
  'Copy the module descriptor into the cogram image buffer.  Normally we'd use the shuttle buffer, but at the point
  'this function is called the shuttle buffer is being used to contain the patch binary, and the cogram image buffer is available.
  if( dest_module_index < hw#MAX_STATIC_MODULES )
     bytemove( @module_descriptor_image, ss__static_module_descriptor_p[dest_module_index], hw#MODULE_DESCRIPTOR_SIZE)
   
  else
     'Index points to a dynamic module (in EEPROM)
   
     'Determine the Module Descriptor address in EEPROM 
     j:= hw#EEPROM_OFFSET__MOD_DESCRIPTORS + ((dest_module_index - hw#MAX_STATIC_MODULES) * hw#MODULE_DESCRIPTOR_SIZE)
     'Read the module descriptor length from the module descriptor in EEPROM
     i2c.ReadLong(hw#I2C_ADDR__BOOT_EEPROM, j + hw#MDES_OFFSET__SIZE, @k)
     'Read the data from EEPROM
     error_code := i2c.ReadBlock(hw#I2C_ADDR__BOOT_EEPROM, j, k, @module_descriptor_image)
  
  if (error_code == hw#ERR__SUCCESS)
    'Get pointer to first socket's description
    j:=@module_descriptor_image + hw#MDES_OFFSET__FIRST_SOCKET

    'Skip ahead to the socket we are looking for
    k:=0
    repeat while(k <> socket_index)
      j := CopyMdesString(j,0)   'Skip socket name
      j += 4                     'Skip flags
      j := CopyMdesString(j,0)   'Skip socket units
      j += 12                    'Skip low, high, default
      ++k

    'Get socket name string
    k:= @g_knob_name + (knob_number * hw#KNOB_NAME_CHARS)
    bytefill(k, hw#ASCII_space, hw#KNOB_NAME_CHARS) 
    j := CopyMdesString(j,k)
    'Get flags
    g_knob_flags[knob_number] := long[j]   
    j+=4
    'Get socket units string
    k:= @g_knob_units + (knob_number * hw#KNOB_UNITS_CHARS)
    bytefill(k, hw#ASCII_space, hw#KNOB_UNITS_CHARS) 
    j := CopyMdesString(j,k)
    'Get low range
    g_knob_range_low[knob_number] := long[j]
    j += 4
    'Get high range
    g_knob_range_high[knob_number] := long[j]
    j += 4
  
  return(error_code)

PRI FormatEeprom | error_code
  'Erase the Module Mask
  ss__module_mask := 0
  error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__MODULE_MASK), ss__module_mask)
  if (error_code == hw#ERR__SUCCESS)
     'Erase the Patch Mask
     ss__patch_mask := 0
     error_code := i2c.WriteWord(hw#I2C_ADDR__BOOT_EEPROM, constant(hw#EEPROM_OFFSET__SYS_CONFIG_BLK + hw#SCB_OFFSET__PATCH_MASK), ss__patch_mask)
  return(error_code)
             
PRI BindKnobToSysresource( knob_number, dest_module_index ) | k
   g_knob_flags[knob_number] := 0
   g_knob_range_low[knob_number] := 0
   g_knob_range_high[knob_number] := 100

   'Set knob name string
   k:= @g_knob_name + (knob_number * hw#KNOB_NAME_CHARS)
   bytefill(k, hw#ASCII_space, hw#KNOB_NAME_CHARS)
   if(dest_module_index ==  hw#SYS_MODULE__GAIN)
      bytemove(k,string("Gain"),4)

   'Set knob units string
   k:= @g_knob_units + (knob_number * hw#KNOB_UNITS_CHARS)
   bytefill(k, hw#ASCII_space, hw#KNOB_UNITS_CHARS)
   bytemove(k,string("%"),1)   

PRI CopyMdesString(string_p, dest_p)
''Copies over a module descriptor string and returns a pointer to the following longword aligned location
''Can be used to jump past a string by setting dest_p to 0 on entry.
  repeat while byte[string_p] <> 0
    if(dest_p <> 0)
      byte[dest_p] := byte[string_p]
      ++dest_p
    ++string_p
  string_p+=1
  if((string_p & $00000003)<>0)
    string_p := (string_p & $fffffffc) + $00000004
  return(string_p)

PRI MEMBUS_write (membus_data, membus_cntl)
  DIRA |= hw#PINGROUP__MEMBUS
  OUTA[23..16] := membus_data 
  OUTA[2..0]   := membus_cntl
  OUTA |= hw#PIN__MEMBUS_CLK
  OUTA &= !hw#PIN__MEMBUS_CLK
  'Now clear the whole memory interface so that the pins can be freely controlled by other cogs
  OUTA &= !(hw#PINGROUP__MEM_INTERFACE | hw#PINGROUP__MEMBUS)
  DIRA &= !hw#PINGROUP__MEMBUS     

PRI MEMBUS_read (membus_cntl) | membus_data
  DIRA &= !hw#PINGROUP__MEMBUS
  OUTA[2..0]   := membus_cntl
  OUTA |= hw#PIN__MEMBUS_CLK
  membus_data := INA[23..16]
  OUTA &= !hw#PIN__MEMBUS_CLK

  'Now clear the whole memory interface so that the pins can be freely controlled by other cogs
  OUTA &= !(hw#PINGROUP__MEM_INTERFACE | hw#PINGROUP__MEMBUS)
  
  return membus_data
    
PRI PLD_enable_PLD_mux

  'Disable the LCD mux (this routes the shared LCD control pins to the PLD)
  OUTA &= !hw#PIN__MEMBUS_CLK 
  OUTA &= !hw#PIN__LCD_MUX
  
PRI LCD_enable_LCD_mux

  'Clear the LCD control pins
  OUTA &= !CONSTANT(hw#PIN__LCD_REGSEL | hw#PIN__LCD_READ | hw#PIN__LCD_ENABLE)
  'Enable the LCD mux (this routes the shared LCD control pins to the LCD)
  OUTA |= hw#PIN__LCD_MUX

PRI LCD_send_command(command)

  'Set the data bus pins as outputs
  DIRA |= hw#PINGROUP__MEMBUS
  
  'Output the LCD command
  OUTA[23..16] := command
  OUTA |=  hw#PIN__LCD_ENABLE
  OUTA &= !hw#PIN__LCD_ENABLE
  
  'Wait for the command to complete
  LCD_wait_while_busy
  
  'Now clear the whole memory interface so that the pins can be freely controlled by other cogs
  OUTA &= !(hw#PINGROUP__MEM_INTERFACE | hw#PINGROUP__MEMBUS)
  DIRA &= !hw#PINGROUP__MEMBUS  

PRI LCD_send_data (char_data)

  'Set the data bus pins as outputs   
  DIRA |= hw#PINGROUP__MEMBUS
  
  'Output the data
  OUTA[23..16] := char_data
  
  'Latch the data
  OUTA |=  hw#PIN__LCD_REGSEL 
  OUTA |=  hw#PIN__LCD_ENABLE  
  OUTA &= !hw#PIN__LCD_ENABLE
  OUTA &= !hw#PIN__LCD_REGSEL
  
  'Wait for the write to complete
  LCD_wait_while_busy

  'Now clear the whole memory interface so that the pins can be freely controlled by other cogs
  OUTA &= !(hw#PINGROUP__MEM_INTERFACE | hw#PINGROUP__MEMBUS)
  DIRA &= !hw#PINGROUP__MEMBUS   

PRI LCD_get_data | read_data

  'Set data pins as inputs
  DIRA &= !hw#PINGROUP__MEMBUS
  'Issue the read sequence
  OUTA |= CONSTANT(hw#PIN__LCD_REGSEL | hw#PIN__LCD_READ)
  OUTA |= hw#PIN__LCD_ENABLE
  'Get the read data
  read_data := INA[23..16]
  'End the read sequence
  OUTA &= !hw#PIN__LCD_ENABLE
  OUTA &= !CONSTANT(hw#PIN__LCD_REGSEL | hw#PIN__LCD_READ)

  'Now clear the whole memory interface so that the pins can be freely controlled by other cogs
  OUTA &= !(hw#PINGROUP__MEM_INTERFACE | hw#PINGROUP__MEMBUS)
  
  'Return the result
  return (read_data)

PRI LCD_wait_while_busy | read_data
  'Set data pins as inputs
  DIRA &= !hw#PINGROUP__MEMBUS

  read_data := hw#LCD_BUSY

  repeat while (read_data & hw#LCD_BUSY)
    OUTA |= hw#PIN__LCD_READ
    OUTA |= hw#PIN__LCD_ENABLE
    'Get the read data
    read_data := INA[23..16]
    'End the read sequence
    OUTA &= !hw#PIN__LCD_ENABLE
    OUTA &= !hw#PIN__LCD_READ
  
PRI LCD_print_string (screen_location, string_ptr) | write_p
  write_p := @ss__display_buffer + screen_location
  'Display string. Never overrun the LCD display buffer (even if the string doesn't zero terminate).
  repeat while (byte[string_ptr] <> 0) and (screen_location < hw#LCD_CHARS)
    byte[write_p] := byte[string_ptr]
    ++string_ptr
    ++write_p
    ++screen_location 

PRI LCD_Clear | i
  repeat i from 0 to (hw#LCD_CHARS / hw#BYTES_PER_LONGWORD)
    ss__display_buffer[i] := $20202020    ' Fill with blank spaces " " ($20's)
    
PRI Update_LCD | i, read_p
  read_p := @ss__display_buffer
  'Set LCD to display DDRAM location
  LCD_send_command(hw#LCD_CMD__HOME_LINE1)
  repeat i from 0 to 31
    if i==16
      LCD_send_command(hw#LCD_CMD__HOME_LINE2)     
    LCD_send_data (byte[read_p + i])

PRI Int_To_3Digit_String(str, i) | place, digit
''Does sprintf(str, "%3d", i);
  str+=2
  repeat place from 0 to 2
    digit :=  hw#ASCII_0 + (i // 10)
    i/=10
    if digit == hw#ASCII_0 and place > 0 and i==0
      digit := hw#ASCII_space
    BYTE[str] := digit
    
    str--

PRI Int_To_3Digit0_String(str, i) | place, digit
''Does sprintf(str, "%03d", i);
  str+=2
  repeat place from 0 to 2
    digit :=  hw#ASCII_0 + (i // 10)
    i/=10
    if digit == hw#ASCII_0 and place > 0 and i==0
      digit := hw#ASCII_0
    BYTE[str] := digit
    
    str--

PRI Int_To_10Digit_String(str, i) | place, digit, length
''Does sprintf(str, "%10d", i);
  str+=9
  length := 0
  repeat place from 0 to 9
    digit :=  hw#ASCII_0 + (i // 10)
    i/=10
    if digit == hw#ASCII_0 and place > 0 and i==0
      digit := hw#ASCII_space
    else
      ++length
    BYTE[str] := digit
    
    str--
    
  return length

PRI Byte_To_4Digit_HexString(str, i) | place, digit
''Does sprintf(str, "0x%02x", i);

  byte[str]   := hw#ASCII_0
  byte[str+1] := hw#ASCII_x

  str+=3
  repeat place from 0 to 1
    digit :=  hw#ASCII_0 + (i // 16)
    i/=16
    if digit > hw#ASCII_9 
      digit += (hw#ASCII_A - hw#ASCII_9 - 1)
    BYTE[str] := digit
    
    str--

PRI Int32_To_10Digit_HexString(str, i) | place, digit
''Does sprintf(str, "0x%08x", i);

  byte[str]   := hw#ASCII_0
  byte[str+1] := hw#ASCII_x

  str+=9
  repeat place from 0 to 7
    digit :=  hw#ASCII_0 + (i // 16)
    i/=16
    if digit > hw#ASCII_9 
      digit += (hw#ASCII_A - hw#ASCII_9 - 1)
    BYTE[str] := digit
    
    str--

PRI AppendString (dest_p, src_p, max_src_len, flags) | i, j, trailing_spaces, append_char

  'Locate end of dest string
  i:=0
  repeat while(byte[dest_p + i] <> 0)
    ++i

  'Copy src string until zero or max_len reached
  j := 0
  trailing_spaces := 0
  repeat while((byte[src_p + j] <> 0) and (j<max_src_len))
   append_char := byte[src_p + j]  
   if(not ((flags & APPEND__NO_SPACES) and (append_char == hw#ASCII_space)))
     'Append the character
     byte[dest_p + i] := append_char
     i++
     
   'Keep track of trailing spaces  
   if (append_char == hw#ASCII_space)
     ++trailing_spaces
   else
     trailing_spaces := 0

   'Increment the source pointer
   ++j

  'Terminate log string with a zero. 
  if((trailing_spaces > 1) and (not(flags & APPEND__NO_SPACES)))
    'If multiple trailing spaces exist, then leave only one of them and drop the rest.  This feature is disabled if the NO_SPACES flag is set
    byte[dest_p + i - trailing_spaces + 1] := 0 
  else
    byte[dest_p + i] := 0

PRI GetModuleNamePointer (module_descriptor_p) | i, j, num_sockets
'' Walks the module descriptor for the module name, and returns a pointer to the module name

  'Get the number of sockets
  num_sockets := long[module_descriptor_p + hw#MDES_OFFSET__NUM_SOCKETS]
  'Get pointer to the data associated with the first socket
  i :=  module_descriptor_p + hw#MDES_OFFSET__FIRST_SOCKET
  'Skip over the data associated with each socket
  repeat j from 1 to num_sockets
    'Skip socket name string
    i :=  SkipStringAndWordAlign(i)
    'Skip socket flags longword 
    i += 4
    'Skip socket units string 
    i :=  SkipStringAndWordAlign(i)
    'Skip range high, range low, and default value longwords (3 longwords total)
    i += 12

  ' Return the pointer to the module name
  return i
     

PRI SkipStringAndWordAlign (string_p)
'' Walks to the end of a string and then updates to the next word aligned address

  'Walk to end of zero terminated text string
  repeat while (byte[string_p] <> 0)
    ++string_p

  'skip the terminating zero  
  ++string_p
  
  'Word align
  if((string_p & $03) <> 0)
    string_p := (string_p & $FFFFFFFC) + $04
  return string_p

PRI AppendVersion(version_p) | i, string_p
'' Appends a version to the version string. The passed pointer points to a longword of the form "$00_rr_rr_rr"
'' When complete, this function will append a string of the form " vrr.rr.rr, "

  AppendString (@g_version_string, string(" v"), 2, APPEND__NORMAL) 
  repeat i from 1 to 3
    if(i == 1)
      Int_To_3Digit_String(@string_3digit_0, byte[version_p + i])
      string_p := @string_3digit_0
    else  
      Int_To_3Digit0_String(@string_3digit_0, byte[@shuttle_buffer + hw#PBIN_OFFSET__PATCH_VERSION + i])
      string_p := @string_3digit_0 + 1
    AppendString (@g_version_string, string_p, 3, APPEND__NO_SPACES)
    if(i <> 3)
      AppendString (@g_version_string, string("."), 1, APPEND__NORMAL)
  AppendString (@g_version_string, string(", "), 2, APPEND__NORMAL)
  
'=======================================================================
'DATA SECTION
'======================================================================= 
DAT

string_3digit_0         byte    "000",0                    'Zero terminated 3 digit string

string_4digit_0         byte    "0000",0                   'Zero terminated 4 digit string

string_10digit_0        byte    "0000000000",0             'Zeri terminated 10 digit string

string_left_arrow_0     byte    $03,$04,$04,0              'Zero terminated 3 character arrow, pointing left, using custom characters (defined below)

                        '------------------------------------
                        'Custom LCD graphics character bitmaps
                        '------------------------------------

custom_lcd_chars        byte    %000_00100  ' Clipping
                        byte    %000_01110
                        byte    %000_11111
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_00000

                        byte    %000_00000  ' Overrun
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_01110
                        byte    %000_10101
                        byte    %000_10001
                        byte    %000_01110              

                        byte    %000_00100  ' Clipping + Overrun
                        byte    %000_01110
                        byte    %000_11111
                        byte    %000_00000
                        byte    %000_01110
                        byte    %000_10101
                        byte    %000_10001
                        byte    %000_01110

                        byte    %000_00001  ' Arrow head left
                        byte    %000_00011
                        byte    %000_00111
                        byte    %000_01111
                        byte    %000_00111
                        byte    %000_00011
                        byte    %000_00001
                        byte    %000_00000

                        byte    %000_00000  ' Arrow body 
                        byte    %000_00000
                        byte    %000_11111
                        byte    %000_11111
                        byte    %000_11111
                        byte    %000_00000
                        byte    %000_00000
                        byte    %000_00000

                        byte    END_OF_LIST 'End of graphics list

'=======================================================================
'CODEC Engine 
'======================================================================= 
                        org
                        
_CODEC_engine_entry     'get pointers to parameters in the SYSTEM STATE block
                        mov     p_frame_counter,PAR    wz
                        mov     p_out_right,PAR
                        add     p_out_right,#hw#SS_OFFSET__OUT_RIGHT
                        mov     p_out_left,PAR
                        add     p_out_left,#hw#SS_OFFSET__OUT_LEFT
                        mov     p_in_right,PAR
                        add     p_in_right,#hw#SS_OFFSET__IN_RIGHT 
                        mov     p_in_left ,PAR
                        add     p_in_left,#hw#SS_OFFSET__IN_LEFT
                        mov     p_ss_flags, PAR
                        add     p_ss_flags, #hw#SS_OFFSET__FLAGS
                        mov     p_clipping_detect, PAR
                        add     p_clipping_detect,#hw#SS_OFFSET__CLIPPING_DETECT

                        mov     display_buffer_p,PAR
                        add     display_buffer_p, #hw#SS_OFFSET__DISPLAY_BUFFER
                        mov     p_debug,PAR
                        add     p_debug, #hw#SS_OFFSET__DEBUG_PASS

                        rdlong  frame_counter, p_frame_counter    ' Initialize the frame counter (generally the frame counter
                                                                  ' will be started at zero).

                        or      outa,PIN_CODEC_WS       ' Set pin HIGH         "1"
                        or      outa,PIN_BCK            ' Set pin HIGH         "1"
                        mov     dira, DIRA_INIT         ' Set pin directions

                        
                        'Setup Counter A to drive SYSCLK 
                        mov     PHSA, #0
                        mov     FRQA, CTR_CODEC_FREQ
                        mov     CTRA, CTR_CODEC_SYSCLK_CONFIG

                        mov     next_sample_time, CNT
                        add     next_sample_time, TICKS_PER_MICROFRAME
                        
                        '====================================
                        'Process Microframe                                    
                        '==================================== 
_sample_loop            mov     r2, #24                 ' Sample is 24 bits


                        '------------------------------------
                        'Update frame counter                                     
                        '------------------------------------
                        add     frame_counter, #1       ' Increment the frame counter  
                        rdlong  r1, p_ss_flags
                        test    r1, FLAG__RESET_FRAME_COUNTER  wc
              if_c      mov     frame_counter, #0

                        '------------------------------------
                        'Synchronize to sampling interval                                  
                        '------------------------------------
                        'Wait for the start of the next microframe   
                        waitcnt next_sample_time, TICKS_PER_MICROFRAME  

                        'Publish the microframe counter change (all effect modules will syncronize to this counter change)
                        wrlong  frame_counter, p_frame_counter
                        'mov     r1,#1      wz,nr        ' Clear the "Z" flag

                        '------------------------------------
                        'Process RIGHT channel sample                                      
                        '------------------------------------
                        rdlong  out_data, p_out_right   ' Get the outgoing data
                        '!!!!! Should be able to delete the following line
                        mov     in_data_right, #0       ' Clear the incoming data                 

                        'Clock in incoming samle and clock out outgoing sample
_bit_loop_right         rcl     out_data, #1  wc        ' Move next bit of outgoing data into "C"
                        andn    outa,PIN_BCK            ' Set BCLK LOW
                        andn    outa,PIN_CODEC_WS       ' Set WS   LOW  
                        muxc    outa,PIN_DATAI          ' Output outgoing data bit
                        or      outa,PIN_BCK            ' Set BCLK HIGH"
                        test    PIN_CODEC_DATAO, ina wc ' Move DATAO bit state into "C" 
                        rcl     in_data_right, #1       ' Shift incoming data into in_data                         
                        djnz    r2, #_bit_loop_right

                        'Left justify incoming 24 bit sample
                        shl     in_data_right,#8    

                        '------------------------------------
                        'Process LEFT channel sample                                     
                        '------------------------------------
                        mov     r2, #24 
                        rdlong  out_data, p_out_left    ' Get the outgoing data
                        '!!!!! Should be able to delete the following line 
                        mov     in_data_left, #0        ' Clear the incoming data

_bit_loop_left          rcl     out_data, #1  wc        ' Move next bit of outgoing data into "C"
                        andn    outa,PIN_BCK            ' Set BCLK LOW
                        or      outa,PIN_CODEC_WS       ' Set WS   HIGH
                        muxc    outa,PIN_DATAI          ' Output outgoing data bit
                        or      outa,PIN_BCK            ' Set BCLK HIGH"
                        test    PIN_CODEC_DATAO, ina wc ' Move DATAO bit state into "C"
                        rcl     in_data_left, #1        ' Shift incoming data into in_data
                        djnz    r2, #_bit_loop_left

                        'Left justify incoming 24 bit sample
                        shl     in_data_left,#8
                        
                        'Write incoming samples
                        wrlong  in_data_left, p_in_left
                        wrlong  in_data_right, p_in_right                                      

                        '------------------------------------
                        'Detect clipping                               
                        '------------------------------------
                        rdlong  r1, p_out_left
                        'Clipping if higher than the high threshold
                        cmps    r1, CLIPPING_THRESHOLD_HIGH wc      
              if_nc     mov     r2, #1
              if_nc     wrlong  r2, p_clipping_detect
                        'Clipping if lower than the low threshold
                        cmps    r1, CLIPPING_THRESHOLD_LOW wc
              if_c      mov     r2, #1
              if_c      wrlong  r2, p_clipping_detect

                        '------------------------------------
                        'Done                                   
                        '------------------------------------
                        jmp     #_sample_loop



'------------------------------------
'Initialized Data                                      
'------------------------------------
CTR_CODEC_SYSCLK_CONFIG   long    %0_00100_000_00000000_000000_000_001100   'Counter init for SYSCLK
                                                                            '  CTRMODE = NCO/PWM single-ended
                                                                            '  PLLDIV  = 0
                                                                            '  BPIN    = 0
                                                                            '  APIN    = 12 CODEC_SYSCLK

CTR_CODEC_FREQ            long    $24924924 
TICKS_PER_MICROFRAME      long    hw#TICKS_PER_MICROFRAME
PIN_CODEC_SYSCLK          long    %00000000_00000000_00010000_00000000 
PIN_BCK                   long    %00000000_00000000_00001000_00000000                                                                              
PIN_DATAI                 long    %00000000_00000000_01000000_00000000                                                                           
PIN_CODEC_DATAO           long    %00000000_00000000_00100000_00000000                                                                            
PIN_CODEC_WS              long    %00000000_00000000_10000000_00000000
CODEC_DATAO_ROT_R         long    14

TEST_MASK                 long    $f0000000

CLIPPING_THRESHOLD_HIGH   long    $7F5C28F5  '1% down from middle (i.e. zero) to max value range (SIGNED)  
CLIPPING_THRESHOLD_LOW    long    $80A3D70B  '1% up from low to middle (i.e. zero) value range

MEMBUS_LOCK_ID            long    0  
DIRA_INIT                 long    hw#PIN__CODEC_WS | hw#PIN__CODEC_BCK | hw#PIN__CODEC_DATAI | hw#PIN__CODEC_SYSCLK

FLAG__RESET_FRAME_COUNTER long    hw#FLAG__RESET_FRAME_COUNTER  
 
'------------------------------------
'Uninitialized Data
'------------------------------------
r1                        res     1
r2                        res     1

next_sample_time          res     1
p_frame_counter           res     1
p_out_right               res     1
p_out_left                res     1
p_in_right                res     1
p_in_left                 res     1
p_debug                   res     1
p_clipping_detect         res     1
p_ss_flags                res     1

in_data_left              res     1
in_data_right             res     1
out_data                  res     1

frame_counter             res     1

lcd_char_index            res     1
display_buffer_p          res     1
current_char_p            res     1

                          fit



'=======================================================================
'DIAGNOSTICS SECTION
'======================================================================= 
CON
LESS_THAN    = 0
GREATER_THAN = 1

VAR

byte  debug_log_string[128]

long  in_l_capture[diag_audio#NUM_CAPTURE_SAMPLES]
long  in_r_capture[diag_audio#NUM_CAPTURE_SAMPLES]

' Audio Diagnostic Control Block
long  system_state_block_p
long  audio_correlation_error
long  phase_adjust
long  diag_audio_flags
long  in_l_capture_p
long  in_r_capture_p
long  diag_audio_gain_shift

' Video Diagnostic Control Block
long  diag_vid__mode
long  diag_vid__in_l_capture_p
long  diag_vid__in_r_capture_p

' Memtest Diagnostic Control Block
long diag_mem__state
long diag_mem__fail_address
long diag_mem__fail_wrote
long diag_mem__fail_read

OBJ

   'Diagnostics objets
   diag_vid       : "COYOTE1_DIAGNOSTIC_Video.spin"   'Video diagnostic
   diag_audio     : "COYOTE1_DIAGNOSTIC_Audio.spin"   'Audio diagnostic
   diag_mem       : "COYOTE1_DIAGNOSTIC_Memory.spin"  'Memory (SRAM) diagnostic   

PRI RunDiagnostics | done, i, j, k, passed
'' This procedure implements the device manufacturing diagnotics.  Once diagnostics are initiated they will  
'' run to completion and never return back to the main OS.  The device must be reset to restore OS operation.

  serial.TX_diagnostic_string(string("--- DIAGNOSTICS START ---"))   
  LCD_Clear
  
  '-------------------------------------
  ' TEST: SRAM Data Walking 1
  '-------------------------------------  
  serial.TX_diagnostic_string(string("Test: SRAM, Data walking 1"))  
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Testing..."))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("SRAM:Data walk 1"))
 
  i:=1
  passed := true
  repeat while i < $100
    'Get the SRAM semaphore
    repeat until not lockset(hw#LOCK_ID__MEMBUS)
  
    'Write data to address 0
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_LOW)
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_MID)
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_HIGH)
    MEMBUS_write(i,hw#MEMBUS_CNTL__WRITE_BYTE)

    'Read data from address 0
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_LOW)
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_MID)
    MEMBUS_write(0,hw#MEMBUS_CNTL__SET_ADDR_HIGH)
    j := MEMBUS_read(hw#MEMBUS_CNTL__READ_BYTE)
    lockclr(hw#LOCK_ID__MEMBUS) 

    'Verify
    ClearLogString
    if i <> j
      AppendLogString(string("  FAIL: Wrote="))
      Byte_To_4Digit_HexString(@string_4digit_0, i)
      AppendLogString(@string_4digit_0)
      AppendLogString(string(", Read=:"))
      Byte_To_4Digit_HexString(@string_4digit_0, j)
      AppendLogString(@string_4digit_0) 
      serial.TX_diagnostic_string(@debug_log_string) 
      passed := false

    'Shift data
    i := i << 1
    
  if(passed)
     serial.TX_diagnostic_string(string("  PASS")) 

  '-------------------------------------
  ' TEST: SRAM Address Walking 1
  '-------------------------------------  
  serial.TX_diagnostic_string(string("Test: SRAM, Address walking 1"))  
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("SRAM:Addr walk 1"))
 
  i:=1
  j:=1
  passed := true
  repeat while i < $200000
    'Get the SRAM semaphore
    repeat until not lockset(hw#LOCK_ID__MEMBUS)
  
    'Write data to address i
    k := i
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_LOW)
    k >>= 8
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_MID)
    k >>= 8
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_HIGH)
    MEMBUS_write(j,hw#MEMBUS_CNTL__WRITE_BYTE)

    'Clear the SRAM semaphore
    lockclr(hw#LOCK_ID__MEMBUS)

    'Shift address word and increment data value
    i := i << 1
    ++j

  i:=1
  j:=1
  repeat while i < $200000
    'Get the SRAM semaphore
    repeat until not lockset(hw#LOCK_ID__MEMBUS)
  
    'Write data to address i
    k := i
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_LOW)
    k >>= 8
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_MID)
    k >>= 8
    MEMBUS_write(k,hw#MEMBUS_CNTL__SET_ADDR_HIGH)
    k := MEMBUS_read(hw#MEMBUS_CNTL__READ_BYTE)

    'Clear the SRAM semaphore
    lockclr(hw#LOCK_ID__MEMBUS)

    'Verify
    ClearLogString
    if k <> j
      AppendLogString(string("  FAIL: Address="))
      Int32_To_10Digit_HexString(@string_10digit_0, i)
      AppendLogString(@string_10digit_0)
      AppendLogString(string(", Wrote=:"))  
      Byte_To_4Digit_HexString(@string_4digit_0, j)
      AppendLogString(@string_4digit_0)
      AppendLogString(string(", Read=:"))
      Byte_To_4Digit_HexString(@string_4digit_0, k)
      AppendLogString(@string_4digit_0) 
      serial.TX_diagnostic_string(@debug_log_string) 
      passed := false

    'Shift address word and increment data value 
    i := i << 1
    ++j
    
  if(passed)
     serial.TX_diagnostic_string(string("  PASS"))

  '-------------------------------------
  ' TEST: SRAM Full Set/Clear
  '-------------------------------------  
  serial.TX_diagnostic_string(string("Test: SRAM, Full set/clear"))  
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("SRAM:Set/Clear  "))
  waitcnt(cnt+40000000)
  
  diag_mem__state := diag_mem#STATE_RUNNING
  diag_mem.start(@diag_mem__state)
  repeat while(diag_mem__state == diag_mem#STATE_RUNNING )
  if (diag_mem__state ==  diag_mem#STATE_PASSED)
    serial.TX_diagnostic_string(string("  PASS"))
  else
    ClearLogString
    AppendLogString(string("  FAIL: Address="))
    Int32_To_10Digit_HexString(@string_10digit_0, diag_mem__fail_address)
    AppendLogString(@string_10digit_0)
    AppendLogString(string(", Wrote=:"))  
    Byte_To_4Digit_HexString(@string_4digit_0, diag_mem__fail_wrote)
    AppendLogString(@string_4digit_0)
    AppendLogString(string(", Read=:"))
    Byte_To_4Digit_HexString(@string_4digit_0, diag_mem__fail_read)
    AppendLogString(@string_4digit_0) 
    serial.TX_diagnostic_string(@debug_log_string) 
  diag_mem.stop

  '------------------------------------
  'EEPROM Test
  '------------------------------------
  serial.TX_diagnostic_string(string("Test: DATA EEPROM"))
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("EEPROMs       "))

  if(DiagEepromTest(hw#I2C_ADDR__DATA_EEPROM, $a5))
    DiagEepromTest(hw#I2C_ADDR__DATA_EEPROM, $5a)

  serial.TX_diagnostic_string(string("Test: BOOT EEPROM"))     
  if(DiagEepromTest(hw#I2C_ADDR__BOOT_EEPROM, $a5))
    DiagEepromTest(hw#I2C_ADDR__BOOT_EEPROM, $5a)
    
  '-------------------------------------
  ' TEST: Click Left
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Click Left"))
  LCD_Clear    
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Click Left      "))
  done := false
  repeat while(not done)
    ReadButtons
    if (ss__flags &  hw#FLAG__BUTTON_0 ) <> 0
      'BUTTON 0 PRESSED
      done := true 'Done
  DiagWaitForButtonRelease

  '-------------------------------------
  ' TEST: Left Blink
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Left Blink"))
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Left Blink      "))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("FAIL        PASS"))
  done := false  
  repeat while(not done)
    i += $00200000
    if (i < 0)
      ss__flags &= !hw#FLAG__LED_0  'LED0 off
    else
      ss__flags |=  hw#FLAG__LED_0  'LED0 on     
    done := DiagCheckForPassFail
    
  ss__flags &= !hw#FLAG__LED_0  'LED0 off  
  DiagWaitForButtonRelease

  '-------------------------------------
  ' TEST: Right Blink
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Right Blink"))
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Right Blink     "))
  done := false  
  repeat while(not done)
    i += $00200000
    if (i < 0)
      ss__flags &= !hw#FLAG__LED_1  'LED0 off
    else
      ss__flags |=  hw#FLAG__LED_1  'LED0 on
    done := DiagCheckForPassFail

  ss__flags &= !hw#FLAG__LED_1  'LED0 off 
  DiagWaitForButtonRelease

  '-------------------------------------
  ' TEST: Knobs
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Knobs"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Knobs"))
  done := false  
  repeat while(not done)
    read_knobs(hw#KNOB_OPERATION__READ) 
    j:=0
    repeat i from 0 to hw#NUM_KNOBS - 1
      Int_To_3Digit_String(@string_3digit_0, ss__knob_position[i] / CONSTANT($7fffffff/100))
      LCD_print_string (hw#LCD_POS__HOME_LINE2+j, @string_3digit_0)
      j+=4
    done := DiagCheckForPassFail

  DiagWaitForButtonRelease

  '-------------------------------------
  ' TEST: Video
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Video")) 
                                                                 'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Video           "))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("FAIL        PASS"))
  diag_vid__mode := diag_vid#MODE__COLOR_BAR
  diag_vid.start(@diag_vid__mode)
  done := false  
  repeat while(not done)
    done := DiagCheckForPassFail
    
  diag_vid.stop
  DiagWaitForButtonRelease
  
  '------------------------------------
  'Expansion port Test
  '------------------------------------
  serial.TX_diagnostic_string(string("Test: Expansion Port"))
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Expansion Port  "))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("            NEXT")) 
  
  done := false
  k := $02
  repeat while (not done)
    done := GetButton1
    i += $08000000 
    
    'Write Configuration Register
    i2c.Start(hw#PINNUM_I2C_SCL)
    i2c.Write(hw#PINNUM_I2C_SCL, $82)
    i2c.Write(hw#PINNUM_I2C_SCL, $03)
    i2c.Write(hw#PINNUM_I2C_SCL, $7e)    
    i2c.Stop(hw#PINNUM_I2C_SCL)
    
    'Write Output 0
    i2c.Start(hw#PINNUM_I2C_SCL)
    i2c.Write(hw#PINNUM_I2C_SCL, $82)
    i2c.Write(hw#PINNUM_I2C_SCL, $01)
    if (i>0)
      i2c.Write(hw#PINNUM_I2C_SCL, $00)  ' Write output low
    else
      i2c.Write(hw#PINNUM_I2C_SCL, $01)  ' Write output high    
    i2c.Stop(hw#PINNUM_I2C_SCL)
    
    'Read Input 1
    i2c.Start(hw#PINNUM_I2C_SCL)
    i2c.Write(hw#PINNUM_I2C_SCL, $82)
    i2c.Write(hw#PINNUM_I2C_SCL, $00)
    i2c.Start(hw#PINNUM_I2C_SCL)
    i2c.Write(hw#PINNUM_I2C_SCL, $83)    
    j := i2c.Read(hw#PINNUM_I2C_SCL, 0)    
    i2c.Stop(hw#PINNUM_I2C_SCL)
  
    if(j & $02)
      LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("SW:ON "))
      if(not(k & $02))
        serial.TX_diagnostic_string(string("Remote button PRESSED")) 
    else
      LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("SW:OFF"))
      if(k & $02)
        serial.TX_diagnostic_string(string("Remote button RELEASED"))
    
    k := j 
    
  DiagWaitForButtonRelease  

  '-------------------------------------
  ' PROMPT: Insert cable OUT-L to IN-L
  '-------------------------------------
  serial.TX_diagnostic_string(string("Test: Audio"))
  serial.TX_diagnostic_string(string("  Remove Audio Cable"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Remove Audio"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("Cable.      NEXT"))
 
  'Start Audio diagnostic engine
  system_state_block_p := @ss__frame_counter
  audio_correlation_error := $ffffffff
  in_l_capture_p := @in_l_capture
  in_r_capture_p := @in_r_capture
  diag_audio_flags :=  0
  diag_audio_gain_shift := 0
  diag_audio.start(@system_state_block_p)
  
  diag_vid__mode := diag_vid#MODE__OSCILLOSCOPE
  diag_vid__in_l_capture_p := @in_l_capture
  diag_vid__in_r_capture_p := @in_r_capture
  diag_vid.start (@diag_vid__mode)   

  DiagWaitForButton1
  DiagWaitForButtonRelease

  { 
  'DEBUG: This section of code was used to determine the appropriate phase_adjust setting      
  done := false
  diag_audio_flags := CONSTANT( diag_audio#FLAG_IN_L {| diag_audio#FLAG_OUT_L} )
  diag_audio_gain_shift := 3
  repeat while(not done)
    done := GetButton1
    Int32_To_10Digit_HexString(@string_10digit_0, audio_correlation_error)
    LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), @string_10digit_0)

    read_knobs(hw#KNOB_OPERATION__READ)
    phase_adjust := ss__knob_position[0] >> 18
    Int32_To_10Digit_HexString(@string_10digit_0, phase_adjust) 
    LCD_print_string (hw#LCD_POS__HOME_LINE1, @string_10digit_0)
  DiagWaitForButtonRelease
  }
  
  'Verify OUTR to INR (These pins are tied together in hardware, so the data should always loop back)
  phase_adjust := $1BE3 
  diag_audio_flags :=  0
  VerifyAudio($02800000, LESS_THAN)

  'Verify not OUTR to INL
  diag_audio_flags :=  diag_audio#FLAG_IN_L
  VerifyAudio($02800000, GREATER_THAN)

  '-------------------------------------
  ' PROMPT: Insert cable OUT-L to IN-L
  '-------------------------------------
  serial.TX_diagnostic_string(string("  Cable OUT-L to IN-L"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Cable OUT-L to"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("IN-L.       NEXT"))

  phase_adjust := $1B50

  'Verify OUTL TO INL
  diag_audio_flags := CONSTANT( diag_audio#FLAG_IN_L| diag_audio#FLAG_OUT_L )
  DiagWaitForButton1
  DiagWaitForButtonRelease
  VerifyAudio($02000000, LESS_THAN)

  'Verify not OUTL to INR
  diag_audio_flags :=  diag_audio#FLAG_OUT_L
  VerifyAudio($02800000, GREATER_THAN)
  
  '-------------------------------------
  ' PROMPT: Insert cable OUT-L to IN-R
  '-------------------------------------
  serial.TX_diagnostic_string(string("  Cable OUT-L to IN-R"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Cable OUT-L to"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("IN-R.       NEXT"))

  phase_adjust := $1C03

  'Verify OUTL TO INR
  diag_audio_flags := diag_audio#FLAG_OUT_L
  DiagWaitForButton1
  DiagWaitForButtonRelease
  VerifyAudio($02800000, LESS_THAN)

  'Verify not OUTL to INL
  diag_audio_flags :=  CONSTANT( diag_audio#FLAG_IN_L | diag_audio#FLAG_OUT_L )
  VerifyAudio($02000000, GREATER_THAN)

  '-------------------------------------
  ' PROMPT: Insert cable OUT-R to IN-L
  '-------------------------------------
  serial.TX_diagnostic_string(string("  Cable OUT-R to IN-L"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Cable OUT-R to"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("IN-L.       NEXT"))  

  phase_adjust := $1B50

  'Verify OUTR TO INL
  diag_audio_flags := diag_audio#FLAG_IN_L
  DiagWaitForButton1
  DiagWaitForButtonRelease
  VerifyAudio($02000000, LESS_THAN)


  '-------------------------------------
  ' PROMPT: Insert cable HEADPHONE-L to IN-L
  '-------------------------------------
  serial.TX_diagnostic_string(string("  Cable HP-L to IN-L"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Cable HP-L to"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("IN-L.       NEXT"))  

  phase_adjust := $0d95
  diag_audio_gain_shift := 3

  'Verify OUTL TO INL
  diag_audio_flags := CONSTANT( diag_audio#FLAG_IN_L| diag_audio#FLAG_OUT_L )
  DiagWaitForButton1
  DiagWaitForButtonRelease
  VerifyAudio($02000000, LESS_THAN)

  'Verify not OUTL to INR
  diag_audio_flags :=  diag_audio#FLAG_OUT_L
  VerifyAudio($02800000, GREATER_THAN)

  '-------------------------------------
  ' PROMPT: Insert cable HEADPHONE-R to IN-L
  '-------------------------------------
  serial.TX_diagnostic_string(string("  Cable HP-R to IN-L"))
  LCD_Clear
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Cable HP-R to"))
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE2+0), string("IN-L.       NEXT"))  

  phase_adjust := $0E08

  'Verify OUTR TO INL
  diag_audio_flags := diag_audio#FLAG_IN_L
  DiagWaitForButton1
  DiagWaitForButtonRelease
  VerifyAudio($02000000, LESS_THAN)


  '-------------------------------------
  ' Stop diagnostic audio and video engine
  '-------------------------------------
  diag_audio.stop
  diag_vid.stop
  
  '-------------------------------------
  ' DIAGNOSTICS COMPLETE
  '-------------------------------------
  serial.TX_diagnostic_string(string("Diagnostics completed."))
  LCD_Clear 
                                                               'xxxxxxxxxxxxxxxx  LCD field width (16 characters)   
  LCD_print_string (CONSTANT(hw#LCD_POS__HOME_LINE1+0), string("Diags Completed"))
  repeat while(true)

PRI VerifyAudio(threshold, comparison)

  'Wait for error correlation to be calculated
  waitcnt(cnt+40000000)
  
  ClearLogString
  if(((comparison == LESS_THAN) and (audio_correlation_error < threshold)) or ((comparison == GREATER_THAN) and (audio_correlation_error > threshold)))
      AppendLogString(string("  PASS "))
  else
      AppendLogString(string("  FAIL "))  
  
  AppendLogString(string("  Correlation error="))
  Int32_To_10Digit_HexString(@string_10digit_0, audio_correlation_error)  
  AppendLogString(@string_10digit_0)
  
  AppendLogString(string(", Expected "))
  if(comparison == LESS_THAN)
     AppendLogString(string(" < "))
  else
     AppendLogString(string(" > "))
  Int32_To_10Digit_HexString(@string_10digit_0, threshold)
  AppendLogString(@string_10digit_0)
  serial.TX_diagnostic_string(@debug_log_string) 
  
PRI DiagEepromTest(addr, data) | j

  ' WRITE $a5 to address $1ffff (last byte of device)
  i2c.Start(hw#PINNUM_I2C_SCL)         
  j := i2c.Write(hw#PINNUM_I2C_SCL, addr | $02)   'NOTE: $02 sets the upper bit of the 17 bit eeprom data bank address
  if (j <> 0)
    ' No acknowledgement on address setup
    serial.TX_diagnostic_string(string("  FAIL: No ACK (W1)"))
  else
    i2c.Write(hw#PINNUM_I2C_SCL, $ff)
    i2c.Write(hw#PINNUM_I2C_SCL, $ff)
    i2c.Write(hw#PINNUM_I2C_SCL, data)
    i2c.Stop(hw#PINNUM_I2C_SCL)
    waitcnt(cnt+16000000) 
    
    ' READ address $1ffff (last byte of device)
    i2c.Start(hw#PINNUM_I2C_SCL)  
    j := i2c.Write(hw#PINNUM_I2C_SCL, addr | $02)
    if (j <> 0)
    ' No acknowledgement on address setup  
      serial.TX_diagnostic_string(string("  FAIL: No ACK (W2)"))
    else
      i2c.Write(hw#PINNUM_I2C_SCL, $ff)
      i2c.Write(hw#PINNUM_I2C_SCL, $ff)
      i2c.Start(hw#PINNUM_I2C_SCL)
      j := i2c.Write(hw#PINNUM_I2C_SCL, addr | $01) 'NOTE: $01 specifies and I2C read operation
      if (j <> 0)
        ' No acknowledgement on address setup   
        serial.TX_diagnostic_string(string("  FAIL: No ACK (R1)"))
      else
        j := i2c.Read(hw#PINNUM_I2C_SCL, 1)
        i2c.Stop(hw#PINNUM_I2C_SCL)
         
        if(j == data)
          serial.TX_diagnostic_string(string("  PASS")) 
        else
          ClearLogString
          AppendLogString(string("  FAIL: Expected="))
          Byte_To_4Digit_HexString(@string_4digit_0, data)
          AppendLogString(@string_4digit_0) 
          AppendLogString(string(",Received="))   
          Byte_To_4Digit_HexString(@string_4digit_0, j)
          AppendLogString(@string_4digit_0) 
          serial.TX_diagnostic_string(@debug_log_string)
          i2c.Stop(hw#PINNUM_I2C_SCL)
          return true   
    
  'End the I2C transaction
  i2c.Stop(hw#PINNUM_I2C_SCL)
  return false
  
PRI DiagCheckForPassFail 
  ReadButtons
  if ((ss__flags & hw#FLAG__BUTTON_0) <> 0)
    serial.TX_diagnostic_string(string("  FAIL"))
    return true
  if ((ss__flags & hw#FLAG__BUTTON_1) <> 0)
    serial.TX_diagnostic_string(string("  PASS"))
    return true
  return false  

PRI GetButton1
  ReadButtons
  if ((ss__flags & hw#FLAG__BUTTON_1) <> 0)
    return true
  return false

PRI DiagWaitForButton1
  ReadButtons
  repeat while((ss__flags & hw#FLAG__BUTTON_1) == 0)
    ReadButtons 

PRI DiagWaitForButtonRelease
  ReadButtons
  repeat while((ss__flags &  (hw#FLAG__BUTTON_0 | hw#FLAG__BUTTON_1)) <> 0)
    ReadButtons

PRI ClearLogString
  debug_log_string[0] := 0

PRI AppendLogString (string_p) | i, j
  'Locate end of log string
  i:=0
  repeat while(debug_log_string[i] <> 0)
    ++i

  'Copy append string
  j:=0
  repeat while(byte[string_p + j] <> 0)
   debug_log_string[i] := byte[string_p + j]
   ++j
   ++i

  'Terminate log string
  debug_log_string[i] := 0 