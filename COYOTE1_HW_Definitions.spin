''=======================================================================  
'' TITLE: COYOTE1_HW_Definitions.spin
''
'' DESCRIPTION:
''    Hardware definitions for the Coyote-1 O/S.
''
'' COPYRIGHT:
''   Copyright (C)2008 Eric Moyer
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
''  Rev  Date      Description
''  ---  --------  ---------------------------------------------------
''  001  07-19-08  Initial Release.
''  002  11-01-08  Add VERSION_STRING_SIZE, MODULE_NAME_CHARS, SCROLL_STATEs, and SCROLL tick counts to support version scrolling 
''
''=======================================================================

CON


  SERIAL_BAUD_RATE        = 28800 
  AUDIO_SAMPLE_RATE       = 44000 'Audio sample rate

  '------------------------------------
  'Propeller pin assignments
  '------------------------------------
  
  'Memory bus  
  PIN__MEMBUS_CNTL_0      = %00000000_00000000_00000000_00000001 'Shared with LCD_READ
  PIN__MEMBUS_CNTL_1      = %00000000_00000000_00000000_00000010 'Shared with LCD_ENABLE
  PIN__MEMBUS_CNTL_2      = %00000000_00000000_00000000_00000100 'Shared with LCD_REGSEL
  PIN__MEMBUS_CLK         = %00000000_00000000_00000000_01000000
  PINGROUP__MEMBUS        = %00000000_11111111_00000000_00000000
  PINGROUP__MEM_INTERFACE = %00000000_00000000_00000000_01000111
  PINGROUP__LCD_INTERFACE = %00001000_11111111_00000000_01000111  
  PINGROUP__MEMBUS_CNTL   = %00000000_00000000_00000000_00000111
  MEMBUS_SHIFT            = 16                                   'Bitshift required to get byte data onto MEMBUS pins
  PIN__LCD_BUSY_FLAG      = %00000000_10000000_00000000_00000000 'BUSY flag position (when reading LCD)  

  'Knob controls
  PIN__KNOB_STROBE        = %00000000_00000000_00000000_00001000  
  PIN__KNOB_SHUNT         = %00000000_00000000_00000000_00010000 'Shared with BUTTON_MUX
  PIN__KNOB_0             = %00000000_00000000_00000000_10000000  
  PIN__KNOB_1             = %00000000_00000000_00000001_00000000  
  PIN__KNOB_2             = %00000000_00000000_00000010_00000000  
  PIN__KNOB_3             = %00000000_00000000_00000100_00000000
  PINNUMBER__KNOB_0       = 7
                        
  'Button controls      
  PIN__BUTTON_MUX         = %00000000_00000000_00000000_00010000 'Shared with KNOB_SHUNT
  PIN__BUTTON_READ        = %00000000_00000000_00000000_00100000
                        
  'Codec interface      
  PIN__CODEC_BCK          = %00000000_00000000_00001000_00000000  
  PIN__CODEC_SYSCLK       = %00000000_00000000_00010000_00000000  
  PIN__CODEC_DATAO        = %00000000_00000000_00100000_00000000  
  PIN__CODEC_DATAI        = %00000000_00000000_01000000_00000000  
  PIN__CODEC_WS           = %00000000_00000000_10000000_00000000
                        
  'LCD interface        
  PIN__LCD_MUX            = %00001000_00000000_00000000_00000000  
  PIN__LCD_READ           = %00000000_00000000_00000000_00000001 'Shared with MEMBUS_CNTL_0
  PIN__LCD_ENABLE         = %00000000_00000000_00000000_00000010 'Shared with MEMBUS_CNTL_1
  PIN__LCD_REGSEL         = %00000000_00000000_00000000_00000100 'Shared with MEMBUS_CNTL_2     
                        
  'EEPROM               
  PIN__EEPROM_SCK         = %00010000_00000000_00000000_00000000  
  PIN__EEPROM_SDA         = %00100000_00000000_00000000_00000000
                        
  'USB Serial           
  PIN__USB_RXD            = %01000000_00000000_00000000_00000000  
  PIN__RSB_TXD            = %10000000_00000000_00000000_00000000  
                        
  'Video                
  PINGROUP__VIDEO         = %00000111_00000000_00000000_00000000  

  '------------------------------------
  'Propeller pin configuration settings
  '------------------------------------

  'Pin direction initial configuraiton (outputs)
  DIRA_INIT = PIN__MEMBUS_CNTL_0 | PIN__MEMBUS_CNTL_1 | PIN__MEMBUS_CNTL_2 | PIN__MEMBUS_CLK | PIN__KNOB_STROBE | PIN__KNOB_SHUNT | PIN__CODEC_BCK | PIN__CODEC_SYSCLK | PIN__CODEC_DATAI | PIN__CODEC_WS | PIN__LCD_MUX | PINGROUP__VIDEO 

  'Pin data initial configuration
  OUTA_INIT = PIN__LCD_MUX

  '------------------------------------
  'PIN Numbers
  '------------------------------------
  PINNUM_I2C_SCL           = 28
  
  '------------------------------------
  'Locks
  '------------------------------------
  LOCK_ID__MEMBUS          = 0            ' Used to control mutually-exclusive access to the MEMBUS resource.
  LOCK_ID__I2C             = 1            ' Used to control mutually-exclusive access to the I2C bus resource.  
  
  '------------------------------------
  'LCD
  '------------------------------------
  
  'LCD Commands
  LCD_CMD__SET_DISPLAY_OPT = %0011_1000   ' Function Set: 8 bit bus, 2 line display, 5x8 dots
  LCD_CMD__LCD_ON          = %0000_1100   ' Display On/Off control: Display on, Cursor off, Blink off
  'LCD_CMD__LCD_ON          = %0000_1111   ' Display On/Off control: Display on, Cursor on, Blink on  
  LCD_CMD__CLEAR_DISPLAY   = %0000_0001   ' Clear Display
  LCD_CMD__MODE_SET        = %0000_0110   ' Entry Mode Set: Cursor increment, Shift disabled 
  LCD_CMD__HOME_LINE1      = %1000_0000   ' Set DDRAM Address: 0x00
  LCD_CMD__HOME_LINE2      = %1011_1000   ' Set DDRAM Address: 0x38
  LCD_CMD__HOME_CGRAM      = %0100_0000   ' Set CGRAM Address: 0x00

  LCD_BUSY                 = %1000_0000   ' Busy flag

  LCD_CHARS                = 32
  LCD_LINE_WIDTH           = 16
  LCD_LINE2_START_ADDR     = $30

  LCD_POS__HOME_LINE1      = 0
  LCD_POS__END_LINE1       = 15
  LCD_POS__HOME_LINE2      = 16
  LCD_POS__END_LINE2       = 31

  '-------------------------------------
  'Version scrolling
  '-------------------------------------
  VERSION_STRING_SIZE      =  156    '  Holds the data for the scrolling version text displayed on the main patch screen
                                     '  Max size =  "DDDDDDDDDDDDDDDD Patch PPP.PPP.PPP, 1111111111111111 RR1.RR1.RR1, 2222222222222222 RR2.RR2.RR2, 3333333333333333 RR3.RR3.RR3, 4444444444444444 RR4.RR4.RR4" + zero termination 
                                     '           =  156 bytes

  SCROLL_STATE__WAIT       = 0
  SCROLL_STATE__SCROLL     = 1

  SCROLL__WAIT_TICKS        = 800    '  Loop ticks before version scrolling begins 
  SCROLL__SCROLL_CHAR_TICKS = 50     '  Loop ticks per scroll character (increasing will slow down scrolling)
  

  '------------------------------------
  'PLD Registers and Control
  '------------------------------------
  
  'CODEC Control Register (CCR)
  CCR__SPARE0          = %1000_0000
  CCR__CODEC_MC2       = %0100_0000
  CCR__CODEC_MC1       = %0010_0000
  CCR__CODEC_MP5       = %0001_0000
  CCR__CODEC_MP4       = %0000_1000
  CCR__CODEC_MP3       = %0000_0100
  CCR__CODEC_MP2       = %0000_0010
  CCR__CODEC_MP1       = %0000_0001

  'General Purpose IO Register 0 (GPIO0)
  GPIO0__SPARE5        = %1000_0000
  GPIO0__SPARE4        = %0100_0000
  GPIO0__SPARE3        = %0010_0000
  GPIO0__SPARE2        = %0001_0000
  GPIO0__SPARE1        = %0000_1000
  GPIO0__LED1          = %0000_0100
  GPIO0__LED0          = %0000_0010
  GPIO0__LCD_BACKLIGHT = %0000_0001

  GPIO0__INIT          = GPIO0__LED1 | GPIO0__LED0 | GPIO0__LCD_BACKLIGHT ' LEDs off, LCD Backlight on.

  'MEMBUS operations
  MEMBUS_CNTL__WRITE_BYTE     = %000     
  MEMBUS_CNTL__READ_BYTE      = %001     
  MEMBUS_CNTL__SET_ADDR_LOW   = %010     
  MEMBUS_CNTL__SET_ADDR_MID   = %011     
  MEMBUS_CNTL__SET_ADDR_HIGH  = %100     
  MEMBUS_CNTL__SET_CCR        = %101     
  MEMBUS_CNTL__SET_GPIO0      = %110        

  '------------------------------------
  'CODEC
  '------------------------------------
  CCR_INIT = CCR__CODEC_MC2 | CCR__CODEC_MC1 | CCR__CODEC_MP4 ' Static mode, 0db gain, 256fs clock, No de-emphasis, MSB-justified data

  '------------------------------------
  'BUTTONS
  '------------------------------------
  NUM_BUTTONS = 2
  
  '------------------------------------
  'KNOBS
  '------------------------------------
  NUM_KNOBS = 4
  
  KNOB_OPERATION__CALIBRATE = 1
  KNOB_OPERATION__READ      = 0   

  KNOB_POSITION_MAX         = $7fff_ffff   'The maximum knob position value (i.e. full clockwise)
  
  CTR_KNOB_SENSE_CONFIG = %0_10101_000_00000000_000000_000_000111    'CTRA Settings:
                                                                     '  CTRMODE = LOGIC !A (Accumulate when pin A is LOW)
                                                                     '  PLLDIV  = 0
                                                                     '  BPIN    = 0
                                                                     '  APIN    = 7 (KNOB_0)

  KNOB_MEASUREMENT_JITTER   = 30                  'Jitter threshold used to debounce input knobs
  KNOB_STICKYNESS_MARGIN    = ($7fff_ffff / 100)  'Sets how close to the "virtual position" you have to turn a sticky knob to have it become unsticky.
            
  '------------------------------------
  'Flags
  '------------------------------------
  FLAG__LCD_BACKLIGHT       = %00000000_00000000_00000000_00000001  ' Set if LCD backlight is on
  FLAG__LED_0               = %00000000_00000000_00000000_00000010  ' Set if LED 0 is on
  FLAG__LED_1               = %00000000_00000000_00000000_00000100  ' Set if LED 1 is on
  FLAG__BUTTON_0            = %00000000_00000000_00000000_00001000  ' Set if button 0 is held down   
  FLAG__BUTTON_1            = %00000000_00000000_00000000_00010000  ' Set if button 1 is held down  
  FLAG__BUTTON_0_EDGE       = %00000000_00000000_00000000_00100000  ' Set if an edge was detected on button 0 (set for 1 microframe only)
  FLAG__BUTTON_1_EDGE       = %00000000_00000000_00000000_01000000  ' Set if an edge was detected on button 1 (set for 1 microframe only)  
                             
  FLAG__RATE_MASK           = %00000000_00000000_00000011_00000000  ' Sample rate bit mask
  FLAG__RATE_44KHz          = %00000000_00000000_00000011_00000000  '    Sample rate = 44 kHz
  FLAG__RATE_22KHz          = %00000000_00000000_00000010_00000000  '    Sample rate = 22 kHz   
  FLAG__RATE_11KHz          = %00000000_00000000_00000001_00000000  '    Sample rate = 11 kHz   
  FLAG__RATE_5_5KHz         = %00000000_00000000_00000000_00000000  '    Sample rate = 5.5 kHz
                             
  FLAG__KNOB_0_INC          = %00000000_00000000_00000100_00000000  ' Set if knob 0 is increasing
  FLAG__KNOB_1_INC          = %00000000_00000000_00001000_00000000  ' Set if knob 1 is increasing
  FLAG__KNOB_2_INC          = %00000000_00000000_00010000_00000000  ' Set if knob 2 is increasing
  FLAG__KNOB_3_INC          = %00000000_00000000_00100000_00000000  ' Set if knob 3 is increasing
                             
  FLAG__LCD_DISABLE         = %00000000_00000000_01000000_00000000  ' Disables LCD update code from running (used during serial RX)
                             
  FLAG__RESET_FRAME_COUNTER = %00000000_00000000_10000000_00000000  ' Resets the frame counter to 0 (will stay at 0 until flag is cleared) so that modules can..
                                                                    ' ..be halted cleanly when unloading them.
                             
  FLAG__GROUP_LED_LCD       = FLAG__LCD_BACKLIGHT | FLAG__LED_0 | FLAG__LED_1 
  
  '------------------------------------  
  ' Angular constants to make object declarations easier
  '------------------------------------  
  ANG_0    = $0000
  ANG_360  = $2000
  ANG_240  = ($2000*2/3)
  ANG_180  = ($2000/2)
  ANG_270  = ($2000*3/4)
  ANG_120  = ($2000/3)
  ANG_90   = ($2000/4)
  ANG_60   = ($2000/6)
  ANG_45   = ($2000/8)
  ANG_30   = ($2000/12)
  ANG_22_5 = ($2000/16)
  ANG_15   = ($2000/24)
  ANG_10   = ($2000/36)
  ANG_5    = ($2000/72)
  ANG_1    = ($2000/360)

  '------------------------------------
  'Capture engine
  '------------------------------------ 
  CAPTURE_STATE__ARM                  = 0
  CAPTURE_STATE__FIND_LOW             = 1
  CAPTURE_STATE__FIND_POS             = 2
  CAPTURE_STATE__CAPTURE              = 3
  CAPTURE_STATE__DONE                 = 4
  CAPTURE_STATE__IDLE                 = 5 

  NUM_CAPTURE_SAMPLES                 = 300
  
  '------------------------------------
  'SYSTEM_STATE block definition
  '------------------------------------
  SS_OFFSET__FRAME_COUNTER            = 0
  SS_OFFSET__OUT_RIGHT                = (1<<2)
  SS_OFFSET__OUT_LEFT                 = (2<<2)
  SS_OFFSET__IN_RIGHT                 = (3<<2)
  SS_OFFSET__IN_LEFT                  = (4<<2)
  SS_OFFSET__KNOB_POS_VIRTUAL_0       = (5<<2) 
  SS_OFFSET__KNOB_POS_VIRTUAL_1       = (6<<2) 
  SS_OFFSET__KNOB_POS_VIRTUAL_2       = (7<<2) 
  SS_OFFSET__KNOB_POS_VIRTUAL_3       = (8<<2) 
  SS_OFFSET__KNOB_POSITION_0          = (9<<2) 
  SS_OFFSET__KNOB_POSITION_1          = (10<<2)
  SS_OFFSET__KNOB_POSITION_2          = (11<<2)
  SS_OFFSET__KNOB_POSITION_3          = (12<<2)
  SS_OFFSET__KNOB_CALIBRATION_0       = (13<<2)
  SS_OFFSET__KNOB_CALIBRATION_1       = (14<<2)
  SS_OFFSET__KNOB_CALIBRATION_2       = (15<<2)
  SS_OFFSET__KNOB_CALIBRATION_3       = (16<<2) 
  SS_OFFSET__KNOB_MEASUREMENT_0       = (17<<2)
  SS_OFFSET__KNOB_MEASUREMENT_1       = (18<<2)
  SS_OFFSET__KNOB_MEASUREMENT_2       = (19<<2)
  SS_OFFSET__KNOB_MEASUREMENT_3       = (20<<2)
  SS_OFFSET__KNOB_PREV_MEAS_0         = (21<<2)
  SS_OFFSET__KNOB_PREV_MEAS_1         = (22<<2)
  SS_OFFSET__KNOB_PREV_MEAS_2         = (23<<2)
  SS_OFFSET__KNOB_PREV_MEAS_3         = (24<<2) 
  SS_OFFSET__FLAGS                    = (25<<2)
  SS_OFFSET__DEBUG_PASS               = (26<<2)
  SS_OFFSET__CAP_STATE                = (27<<2)    
  SS_OFFSET__CAP_SAMPLE_INTERVAL      = (28<<2)           
  SS_OFFSET__NUM_STATIC_MODULES       = (29<<2)  
  SS_OFFSET__STATIC_MOD_DSC_P_0       = (30<<2) 
  SS_OFFSET__STATIC_MOD_DSC_P_1       = (31<<2) 
  SS_OFFSET__STATIC_MOD_DSC_P_2       = (32<<2) 
  SS_OFFSET__STATIC_MOD_DSC_P_3       = (33<<2)
  SS_OFFSET__SHUTTLE_BUFFER_P         = (34<<2)
  SS_OFFSET__RPC_CONTROL              = (35<<2)
  SS_OFFSET__LED0_SOCKET              = (36<<2)
  SS_OFFSET__LED1_SOCKET              = (37<<2)
  SS_OFFSET__BUTTON0_SOCKET           = (38<<2)
  SS_OFFSET__BUTTON0_TGLE_SOCKET      = (39<<2) 
  SS_OFFSET__BUTTON1_SOCKET           = (40<<2)
  SS_OFFSET__BUTTON1_TGLE_SOCKET      = (41<<2)
  SS_OFFSET__PATCH_NUMBER             = (42<<2)
  SS_OFFSET__MODULE_MASK              = (43<<2)
  SS_OFFSET__PATCH_MASK               = (44<<2)
  SS_OFFSET__CLIPPING_DETECT          = (45<<2)
  SS_OFFSET__OVERRUN_DETECT           = (46<<2)
  SS_OFFSET__GAIN_IN_SOCKET           = (47<<2)
  SS_OFFSET__GAIN_OUT_SOCKET          = (48<<2)
  SS_OFFSET__GAIN_CONTROL_SOCKET      = (49<<2) 
  SS_OFFSET__DISPLAY_BUFFER           = (50<<2)
  SS_OFFSET__PATCH_NAME               = SS_OFFSET__DISPLAY_BUFFER + LCD_CHARS
  SS_OFFSET__CAP_SAMPLES              = SS_OFFSET__PATCH_NAME + PATCH_NAME_CHARS    
  SS_OFFSET__UNUSED                   = SS_OFFSET__CAP_SAMPLES + ((NUM_CAPTURE_SAMPLES)<<2)    
  SS_OFFSET__LAST_ENTRY               = SS_OFFSET__UNUSED


  '------------------------------------
  'ASCII Characters
  '------------------------------------
  ASCII_space  = $20  
  ASCII_0      = $30
  ASCII_9      = $39
  ASCII_A      = $41
  ASCII_K      = $4B
  ASCII_colon  = $3A
  ASCII_x      = $78

  'Custom LCD chars
  ASCII_CUSTOM__CLIP                  = $00
  ASCII_CUSTOM__OVERRUN               = $01
  ASCII_CUSTOM__CLIP_AND_OVERRUN      = $02

  '------------------------------------
  'Socket flags
  '------------------------------------
  SOCKET_FLAG__INPUT                  = $800000_00
  SOCKET_FLAG__SIGNAL                 = $200000_00
  SOCKET_FLAG__INITIALIZATION         = $080000_00

  '------------------------------------
  'Segmentation flags
  '------------------------------------
  NO_SEGMENTATION                     = 0

  '------------------------------------
  'Sockets
  '------------------------------------
  CONTROL_SOCKET_MAX_VALUE            = $7fffffff    'Maximum value a control socket can output (or should ever receive as an input)
  
  '------------------------------------
  'Modules
  '------------------------------------
  MAX_STATIC_MODULES                  = 4            'Maximum number of modules compiled into the code
  MAX_ACTIVE_MODULES                  = 4            'Maximum number of modules executing at one timme
  MAX_DYNMAIC_MODULES                 = 16           'Maxumym number of modules located in EEPROM
  MAX_PATCHES                         = 15


  'Module descriptor offsets
  MDES_OFFSET__FORMAT                 = 0            'Module descriptor format identifier
  MDES_OFFSET__SIZE                   = (1<<2)       'Module descriptor size
  MDES_OFFSET__CODE_SIZE              = (2<<2)       'Code size
  MDES_OFFSET__CODE_P                 = (3<<2)       'Pointer to the code (in main RAM) 
  MDES_OFFSET__SIGNATURE              = (4<<2)       'Module signature
  MDES_OFFSET__REVISION               = (5<<2)       'Module revision
  MDES_OFFSET__MICROFRAME_REQ         = (6<<2)       'Microframe requirement
  MDES_OFFSET__HEAP_REQ               = (7<<2)       'Heap requirement (SRAM)
  MDES_OFFSET__RAM_REQ                = (8<<2)       'RAM requirement (internal propeller RAM)
  MDES_OFFSET__RESERVED0              = (9<<2)       '(Reserved for future use)
  MDES_OFFSET__RESERVED1              = (10<<2)      '(Reserved for future use) 
  MDES_OFFSET__RESERVED2              = (11<<2)      '(Reserved for future use) 
  MDES_OFFSET__RESERVED3              = (12<<2)      '(Reserved for future use) 
  MDES_OFFSET__NUM_SOCKETS            = (13<<2)      'Number of Sockets
  MDES_OFFSET__FIRST_SOCKET           = (14<<2)      'Offset of first socket data
  
  'Module descriptor format identifiers         
  MDES_FORMAT_1                       = $3130444d    'Format 1 ('MD01" in ASCII)
  
  '------------------------------------
  'Shuttle Buffer
  '------------------------------------
  SHUTTLE_BUFFER_SIZE_LW              = 512         'The size of the shuttle buffer, in longwords
                                                     
  '------------------------------------              
  'Patches                                           
  '------------------------------------              
  PATCH_NUMBER_NONE                   = $ff         'Indicates that the patch has no bank number (used for host-loaded patches)
  PATCH_NAME_CHARS                    = 16          'Length of patch name
  PATCH_AUTHOR_CHARS                  = 16          'Length of patch author
                                                     
  'Patch binary image offsets
  PBIN_OFFSET__FORMAT                 = 0           'Patch format identifier
  PBIN_OFFSET__LENGTH                 = 4           'Patch length                        
  PBIN_OFFSET__PATCH_NAME             = 8           'Patch Name
  PBIN_OFFSET__AUTHOR_NAME            = PBIN_OFFSET__PATCH_NAME + PATCH_NAME_CHARS
  PBIN_OFFSET__PATCH_VERSION          = PBIN_OFFSET__AUTHOR_NAME + PATCH_AUTHOR_CHARS
  PBIN_OFFSET__RESERVED1              = PBIN_OFFSET__PATCH_VERSION + 4
  PBIN_OFFSET__RESERVED2              = PBIN_OFFSET__RESERVED1 + 4
  PBIN_OFFSET__RESERVED3              = PBIN_OFFSET__RESERVED2 + 4 
  PBIN_OFFSET__SYS_RESOURCES          = PBIN_OFFSET__RESERVED3 + 4  'System resource location list
                                                     
  PBIN_END_OF_RESOURCE_LIST           = $ffffffff   'Marks the end of the system resource list
  
  PBIN_END_OF_EFFECT_LIST             = $ffffffff   'Marks the end if the effects list  
  PBIN_EFFECT_ENTRY_SIZE              = 4 + 4 + 16  'Size of effect entry (signature=4 + location=4 + name=16)

  PBIN_END_OF_CONDUIT_LIST            = $ffffffff   'Marks the end of the conduit list
  
  PBIN_END_OF_ASSIGNMENT_LIST         = $ffffffff   'Marks the end of the assignment list
  
  '------------------------------------
  'RPC (Remote Procedure Calls)
  '------------------------------------
  RPC_FLAG__EXECUTE_REQUEST           = $40000000
  RPC_FLAG__EXECUTE_ACK               = $80000000

  RPC_CMD__MASK                       = $000000ff   'Bitmask of the command field
  RPC_DATA0_MASK                      = $0000ff00   'Bitmask of the data0 field
  RPC_DATA0_SHIFT                     = 8           'But shift to retrieve data0 into LSB
  
  RPC_CMD__NONE                       = $00000000 
  RPC_CMD__PATCH_RUN                  = $00000001   'Run the patch in the shuttle buffer
  RPC_CMD__PATCH_FETCH                = $00000002   'Fetch a patch from eeprom to shuttle buffer
  RPC_CMD__PATCH_STORE                = $00000003   'Store a patch from shuttle buffer to eeprom
  RPC_CMD__MODULE_FETCH               = $00000004   'Fetch a module from eeprom to shuttle buffer
  RPC_CMD__MODULE_STORE               = $00000005   'Store a module from shuttle buffer to eeprom  
  RPC_CMD__MODULE_DESC_FETCH          = $00000006   'Fetch a module descriptor from eeprom to shuttle buffer 
  RPC_CMD__MODULE_DESC_STORE          = $00000007   'Store a module descriptor from shuttle buffer to eeprom
  RPC_CMD__FORMAT_EEPROM              = $00000008   'Format the EEPROM
  RPC_CMD__MODULE_DELETE              = $00000009   'Deletes a module from EEPROM
  RPC_CMD__PATCH_DELETE               = $0000000a   'Deletes a patch from EEPROM
  RPC_CMD__MCB_FETCH                  = $0000000b   'Copy the Module Control Blocks to the shuttle buffer
  RPC_CMD__GET_PATCH_INFO             = $00000040   'Gets the names of all patches 
  

  '------------------------------------
  'EEPROM Organization
  '------------------------------------
  EEPROM_OFFSET__MODULES              = $00008000   ' Contains 16 2K Modules
  EEPROM_OFFSET__MOD_DESCRIPTORS      = $00010000   ' Contains 16 2K Module Descriptors
  EEPROM_OFFSET__PATCHES              = $00018000   ' Contains 15 2K Patches
  EEPROM_OFFSET__SYS_CONFIG_BLK       = $0001F800   ' Contains 2K System Configuration Block (SCB)

  MODULE_SIZE                         = $00000800
  MODULE_DESCRIPTOR_SIZE              = $00000800
  PATCH_SIZE                          = $00000800
  CONFIG_BLOCK_SIZE                   = $00000800


  I2C_ADDR__BOOT_EEPROM               = $A0         ' I2C BOOT EEPROM Device Address
  I2C_ADDR__DATA_EEPROM               = $A4         ' I2C DATA EEPROM Device Address (Second EEPROM device; available for user applications)

  EEPROM_PAGE_WRITE_SIZE              = 256         ' The page write size supported by the EEPROM device
  
  '------------------------------------
  'System Configuration Block Organization
  '------------------------------------
  SCB_OFFSET__MODULE_MASK             = 0
  SCB_OFFSET__PATCH_MASK              = 2
  SCB_OFFSET__CURRENT_PATCH           = 4

  '------------------------------------
  'SYSTEM RESOURCE MODULES
  '------------------------------------
  SYS_MODULE_FLAG                     = $80

  SYS_MODULE__AUDIO_IN_L              = $80
  SYS_MODULE__AUDIO_IN_R              = $81
  SYS_MODULE__AUDIO_OUT_L             = $82
  SYS_MODULE__AUDIO_OUT_R             = $83 
  SYS_MODULE__KNOB0                   = $84
  SYS_MODULE__KNOB1                   = $85
  SYS_MODULE__KNOB2                   = $86
  SYS_MODULE__KNOB3                   = $87
  SYS_MODULE__BUTTON0                 = $88
  SYS_MODULE__BUTTON1                 = $89
  SYS_MODULE__LED0                    = $8a
  SYS_MODULE__LED1                    = $8b
  SYS_MODULE__GAIN                    = $8c 

  '------------------------------------
  'Module Control Blocks
  '------------------------------------
  MAX_SOCKETS_PER_MODULE              = 32

  MCB_OFFSET__SS_BLOCK_P              = 0            'Pointer to the SYSTEM_STATUS block
  MCB_OFFSET__HEAP_BASE_P             = (1<<2)       'Pointer to the module's granted heap space
  MCB_OFFSET__RAM_BASE_P              = (2<<2)       'Pointer to the module's granted RAM space
  MCB_OFFSET__MICROFRAME_BASE         = (3<<2)       'The module's granted microframe base number
  MCB_OFFSET__RUNTIME_FLAGS           = (4<<2)       '(Reserved for future use)   
  MCB_OFFSET__RESERVED0               = (5<<2)       '(Reserved for future use)
  MCB_OFFSET__RESERVED1               = (6<<2)       '(Reserved for future use)
  MCB_OFFSET__RESERVED2               = (7<<2)       '(Reserved for future use)
  MCB_OFFSET__RESERVED3               = (8<<2)       '(Reserved for future use)    
  MCB_OFFSET__SOCKET_EXCHANGE         = (9<<2)       'The start of the "socket exchange" area (1 longword for each possible socket in a module)
  MSB_OFFSET__LAST_SOCKET_EXC_LW      = MCB_OFFSET__SOCKET_EXCHANGE + (MAX_SOCKETS_PER_MODULE << 2) - 4    
  MCB_OFFSET__LAST_LONGWORD           = MSB_OFFSET__LAST_SOCKET_EXC_LW
  
  MCB_SIZE_LONGWORDS                  = MAX_SOCKETS_PER_MODULE  +  (MCB_OFFSET__SOCKET_EXCHANGE >> 2)

  MODULE_NAME_CHARS                   = 16           'Number of characters (max) in a module name
  
  '------------------------------------
  'Error Codes
  '------------------------------------ 
  ERR__SUCCESS                        = 0            'Indicates that no error occurred

  'Patch load errors   
  ERR__MODULE_NOT_FOUND               = 1            'Patch specified a module which could not be found in RAM or EEPROM
  ERR__MAX_ACTIVE_MOD_EXCEEDED        = 2            'Exeeded the max number of allowable active modules
  ERR__CONDUIT_ENG_START_FAILED       = 3            'Failed to start the conduit engine
  ERR__MODULE_COG_START_FAILED        = 4            'Failed to start the module
  ERR__I2C_WRITE_FAIL                 = 5
  ERR__I2C_WRITE_TIMEOUT              = 6
  ERR__INDEXED_MODULE_DNE             = 7            'The indexed module does not exist
  ERR__ILLEGAL_MODULE_INDEX           = 8
  ERR__I2C_READ_FAIL                  = 9
  ERR__ILLEGAL_PATCH_INDEX            = 10
  ERR__OUT_OF_SRAM                    = 11           'The modules associated with a patch requested more heap space than was available
  ERR__OUT_OF_RAM_POOL                = 12           'The modules associated with a patch requested more RAM pool space than was available

  '------------------------------------
  'Miscellaneous
  '------------------------------------
  NO_COG                              = -1           'Returned by cognew when no cog is available

  '------------------------------------
  'Knob Managment
  '------------------------------------
  KNOB_NAME_CHARS                     = 16           'Max length of knob name text (inherited from socket names)
  KNOB_UNITS_CHARS                    = 16           'Max length of units text  (inherited from socket "units" text in module descriptor)

  '------------------------------------
  'SRAM
  '------------------------------------
  SRAM_CHIP_CAPACITY                  = (512 * 1024) 'Storage capacity of each SRAM chip (in bytes)
  SRAM_SIZE                           = 3 * SRAM_CHIP_CAPACITY     'Total SRAM size

  '------------------------------------
  'RAM Pool
  '------------------------------------
  RAM_POOL_SIZE_BYTES                 = 1024 * 4     'Size of the internal RAM pool available to modules
  RAM_POOL_SIZE_LONGWORDS             = RAM_POOL_SIZE_BYTES/4
 
  '------------------------------------
  'Unit Conversions
  '------------------------------------
  MSEC_PER_SEC                        = 1000         'Milliseconds per second
  INT_TO_FXP_16_16                    = $0001_0000   'Conversion factor from integer to 16.16 fixed point
  BYTES_PER_LONGWORD                  = 4
  TICKS_PER_MICROFRAME                = 1792         'System counter ticks per microframe
  
PUB main
  'null routine                                         