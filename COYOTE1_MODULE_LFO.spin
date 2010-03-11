''=======================================================================  
'' TITLE: COYOTE1_MODULE_LFO.spin
''
'' DESCRIPTION:
''   A Low Frequency Oscillator utility module.
''
''   INPUTS:
''      RATE:         Controls the frequency of the LFO.  A change in rate will override
''                    the current tap tempo setting (if one has been established via
''                    the TAP input.
''
''      +TAP:         Tap tempo.  Two trigger events (low to high) on tap tempo will
''                    override the rate setting and replace the rate with the calculated
''                    tap tempo.
''
''      TAP MULTIPLE  Tap multiple. Sets the number of beats per physical "tap" on the tap 
''
''      DEPTH:        Controls the depth of the LFO amplitude range.  (The max output
''                    will always be 100%.  This parameter controls what the level of
''                    the output is when it is as the lowest point in its sweep).
''
''      SHAPE:        The shape of the output waveform
''                       1 = Square 
''                       2 = Triangle 
''                       3 = Sine
''
''      +BYPASS:      Effect bypass control.  When bypassed, the LFO output 100%.
''
''   OUTPUTS:
''      LFO:          Low Frequency Osillator output
''
''      +ON:          Set when effect is active (i.e. not bypassed).
''
''      +RATE BLINK   Blinks the LFO rate (for display to an LED).
''
'' COPYRIGHT:
''   Copyright (C)2009 Eric Moyer
''
'' LICENSING:
''
''   This program module is free software: you can redistribute it and/or modify
''   it under the terms of the GNU General Public License as published by
''   the Free Software Foundation, either version 3 of the License, or
''   (at your option) any later version.
''
''   This program module is distributed in the hope that it will be useful,
''   but WITHOUT ANY WARRANTY; without even the implied warranty of
''   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''   GNU General Public License for more details.
''
''   You should have received a copy of the GNU General Public License
''   along with this program module.  If not, see <http://www.gnu.org/licenses/>.
''   
''======================================================================= 
''
''  REVISION HISTORY:
''
''  Rev      Date      Description
''  -------  --------  ---------------------------------------------------
''  1.00.00  11-18-08  Initial creation.
''  1.00.01  02-23-09  Implement wave shapes
''  1.00.02  02-24-09  Debug.  Basic functionality working.  Tap tempo not yet implemented.
''                     Depth not functioning yet as intended.
''  1.00.03  02-24-09  Correct depth behavior
''  2.00.00  02-25-09  Add "+TAP BLINK" output socket.
''  2.00.01  02-25-09  Implement "+TAP"
''                     Change module signature
''  3.00.00  05-12-09  Add TAP MULTIPLE socket
''
''=======================================================================  
CON

  ' Low frequency oscillator(LFO) period definitions
  LFO_PERIOD_MIN_MSEC         = 10
  LFO_PERIOD_MAX_MSEC         = 5000

  ' Wave shapes
  SHAPE_SINE                  = 1
  SHAPE_SQUARE                = 2
  SHAPE_TRIANGLE              = 3
  NUM_WAVE_SHAPES             = 3
      
OBJ
  hw        :       "COYOTE1_HW_Definitions.spin"  'Hardware definitions       

PUB get_module_descriptor_p
  ' Store the main RAM address of the module's code into the module descriptor. 
  long[ @_module_descriptor + hw#MDES_OFFSET__CODE_P] := @_module_entry
  ' Return a pointer to the module descriptor 
  return (@_module_descriptor)

DAT

'------------------------------------
'Module Descriptor
'------------------------------------
_module_descriptor      long    hw#MDES_FORMAT_1                                       'Module descriptor format
                        long    (@_module_descriptor_end - @_module_descriptor)        'Module descriptor size (in bytes)
                        long    (@_module_end - @_module_entry)                        'Module legth
                        long    0                                                      'Module code pointer (this is a placeholder which gets overwritten during
                                                                                       '   the get_module_descriptor_p() call) 
                        long    $44_80_00_01                                           'Module Signature
                        long    $00_03_00_00                                           'Module revision  (xx_AA_BB_CC = a.b.c)
                        long    0                                                      'Microframe requirement
                        long    0                                                      'SRAM requirement (heap)
                        long    0                                                      'RAM  requirement (internal propeller RAM)
                        long    0                                                      '(RESERVED0) - set to zero to ensure compatability with future OS versions
                        long    0                                                      '(RESERVED1) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED2) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED3) - set to zero to ensure compatability with future OS versions  
                        long    9                                                      'Number of sockets

                        'Socket 0
                        byte    "Rate",0                                               'Socket name 
                        long    0 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    "mSec",0                                               'Units  
                        long    LFO_PERIOD_MIN_MSEC                                    'Range Low
                        long    LFO_PERIOD_MAX_MSEC                                    'Range High
                        long    500                                                    'Default Value

                        'Socket 1
                        byte    "+Tap",0                                               'Socket name   
                        long    1 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units  
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value

                        'Socket 2
                        byte    "Tap Multiple",0                                       'Socket name   
                        long    2 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units  
                        long    1                                                      'Range Low          
                        long    8                                                      'Range High         
                        long    1                                                      'Default Value

                        'Socket 3
                        byte    "Depth",0                                              'Socket name  
                        long    4 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    "%",0                                                  'Units  
                        long    0                                                      'Range Low            
                        long    100                                                    'Range High
                        long    100                                                    'Default Value

                        'Socket 4
                        byte    "Shape",0                                              'Socket name  
                        long    4 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    "LFO Wave Shape",0                                     'Units  
                        long    1                                                      'Range Low            
                        long    3                                                      'Range High
                        long    1                                                      'Default Value

                        'Socket 5
                        byte    "+Bypass",0                                            'Socket name 
                        long    5 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    0                                                      'Default Value

                        'Socket 6
                        byte    "LFO",0                                                'Socket name 
                        long    6                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value
                        
                        'Socket 7
                        byte    "+On",0                                                'Socket name 
                        long    7                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value

                        'Socket 8
                        byte    "+Rate Blink",0                                        'Socket name 
                        long    8                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value

                        byte    "LFO",0                                                'Module name
                        long    hw#NO_SEGMENTATION                                     'Segmentation 

_module_descriptor_end  byte    0    


DAT
                        
'------------------------------------
'Module Code 
'------------------------------------
                        org
                        
_module_entry
                        mov     p_module_control_block, PAR                     'Get pointer to Module Control Block
                        rdlong  p_system_state_block, p_module_control_block    'Get pointer to System State Block

                        'Initialize pointers into System State block
                        mov     p_ss_frame_counter,  p_system_state_block
                        mov     p_ss_overrun_detect, p_system_state_block
                        add     p_ss_overrun_detect, #(hw#SS_OFFSET__OVERRUN_DETECT)

                        'Initialize pointers to the socket exhange
                        mov     p_socket_rate,         p_module_control_block
                        add     p_socket_rate,         #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (0 << 2))
                        mov     p_socket_tap,          p_module_control_block
                        add     p_socket_tap,          #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (1 << 2))
                        mov     p_socket_tap_multiple, p_module_control_block
                        add     p_socket_tap_multiple, #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (2 << 2))
                        mov     p_socket_depth,        p_module_control_block
                        add     p_socket_depth,        #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (3 << 2)) 
                        mov     p_socket_shape,        p_module_control_block
                        add     p_socket_shape,        #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (4 << 2)) 
                        mov     p_socket_bypass,       p_module_control_block
                        add     p_socket_bypass,       #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (5 << 2))
                        mov     p_socket_lfo,          p_module_control_block
                        add     p_socket_lfo,          #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (6 << 2)) 
                        mov     p_socket_on,           p_module_control_block
                        add     p_socket_on,           #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (7 << 2))
                        mov     p_socket_rate_blink,   p_module_control_block
                        add     p_socket_rate_blink,   #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (8 << 2)) 

'------------------------------------
'Effect processing loop
'------------------------------------

                        '------------------------------------
                        'Init
                        '------------------------------------
                        mov    previous_rate, #0
                        sub    previous_rate, #1                                'Set previoius_rate to $ffffffff so that the initial rate will be detected as a change
                        mov    tap_interval, #0
                        
                        '------------------------------------
                        'Sync
                        '------------------------------------
                        rdlong  previous_microframe, p_ss_frame_counter         'Initialize previous microframe
                        
                        'Wait for the beginning of a new microframe
_frame_sync             rdlong  current_microframe, p_ss_frame_counter
                        cmp     previous_microframe, current_microframe  wz
              if_z      jmp     #_frame_sync                                    'If current_microframe = previoius_microframe

                        'Verify sync, and report an overrun condition if it has occurred.
                        '
                        'NOTE: An overrun condition is reported to the OS by writing a non-zero value to the "overrun detect" field in the
                        '      SYSTEM_STATE block.  The code below writes the value of current_microframe in order to conserve code space,
                        '      achieve portability, and limit execution time. That value will be non-zero 99.9999999767169% of the time,
                        '      which is sufficiently reliable for overrun reporting
                        '
                        add     previous_microframe, #1
                        cmp     previous_microframe, current_microframe  wz
              if_nz     wrlong  current_microframe, p_ss_overrun_detect
                        
                        mov     previous_microframe, current_microframe         'previous_microframe = current_microframe
                        
                        '------------------------------------
                        'Bypass
                        '------------------------------------
                        'Read bypass state
                        rdlong  r1, p_socket_bypass  
                        cmp     SIGNAL_TRUE, r1   wc, wz

                        'Update on/off indication
        if_c_or_z       mov     r2, #0
        if_nc_and_nz    mov     r2, SIGNAL_TRUE
                        wrlong  r2, p_socket_on
                        
                        'If bypassed, then output 100% as LFO value 
        if_c_or_z       wrlong  CONTROL_SOCKET_MAX_VALUE, p_socket_lfo
        if_c_or_z       jmp     #_frame_sync

                        '------------------------------------
                        'Update rate if "RATE" socket input changes
                        '------------------------------------

                        'If rate has not changed, then done processing (jump to end of this section)
                        rdlong  x, p_socket_rate
                        cmp     x, previous_rate   wz
        if_z            jmp     #_rate_done

                        'Remember the new rate  
                        mov     previous_rate, x                                

                        'Determine the angular step per sample
                        shr     x, #21
                        add     x, #1
                        mov     y, LFO_PERIOD_RANGE
                        call    #_mult
                        shr     y, #10
                        add     y, #LFO_PERIOD_MIN_MSEC

                        mov     x, LFO_CALCULATION_NUMERATOR
                        call    #_div19
                        and     x, QUOTIENT_MASK_19                              ' x now contains the 16.16 Fixed point angular step
                        mov     rate_step_16_16_fxp, x 
_rate_done

                        '--------------------------------------
                        ' Process "+TAP" input
                        '--------------------------------------
                        
                        rdlong   r1, p_socket_tap
                        cmp      SIGNAL_TRUE, r1   wc, wz   
        if_nc_and_nz    mov      r2, #0
        if_nc_and_nz    jmp      #_tap_done
                        mov      r2, #1

                        cmp      previous_tap, #0  wz
        if_nz           jmp      #_tap_done

                        'A tap event was detected. Adopt the new tap interval
                        mov      x, ANGLE_360
                        shl      x, #16
                        mov      y, tap_interval
                        
                        call     #_div16
                        and      x, QUOTIENT_MASK_16

                        'Multiply the tap rate by the TAP multiple
                        rdlong   y, p_socket_tap_multiple                       ' y = TAP MULTIPLE
                        shr      y, #28                                         ' y >>= 28  (strip down to a 4 bit value from 0 to 7)
                        add      y, #1                                          ' y += 1    (y now has the range 1 to 8 across the full knob range)
                        call     #_mult                                         ' y = x * y
                        mov      rate_step_16_16_fxp, y                         ' rate_step_16_16_fxp = y

                        mov      angle_16_16_fxp, #0                            ' Clear angle so that LFO sweep sychronizes to the button press
                        mov      angle_16, NEGATIVE_ONE                         ' Set angle_16 to -1 so that the 360 degree rollover detection
                                                                                '     fires immediately, causing the LED to blink immediately.
                        mov      tap_interval, #0                               ' Clear the tap interval for the next tap detection
        
_tap_done               mov      previous_tap, r2                               ' Remember the previous tap button state
                        add      tap_interval, #1                               ' Increment the tap interval counter (for tap interval measurement)
                        
                        '------------------------------------
                        'Udpate LFO (Low Frequeency Oscillator) Angle
                        '------------------------------------

                        'Increment the LFO angle 
                        add     angle_16_16_fxp, rate_step_16_16_fxp            ' Increment the current angle, based on LFO rate step
                        mov     old_angle_16, angle_16                          ' Remember the previous 16 bit angle (for "Blink Rate" display)
                        mov     angle_16, angle_16_16_fxp
                        shr     angle_16, #16                                   ' angle_16 now contains integer angle


                        '--------------------------------------
                        ' Shape: SQUARE
                        '--------------------------------------
                        rdlong  r1, p_socket_shape
                        mov     selection_threshold, WAVE_SHAPE_SELECT_THRESH_STEP
                        cmp     r1, selection_threshold  wc
        if_nc           jmp     #_shape_triangle                                ' If shape not set to 'Square', jump to 'Triangle'


                        '            $0000 $1000 $2000 $3000  
                        '            |     |     |     |
                        '                        
                        '     $FFFF  +-----+     +-----+
                        '            |     |     |     |
                        '            |     |     |     |
                        '            |     |     |     |
                        '            |     |     |     |
                        '            |     |     |     |
                        '     $0000  +     +-----+     +---
                        '
                        '
                        mov      sin, #0                                         ' sin = $0000;
                        test     angle_16,ANGLE_180 wz                           ' if ( angle_16 & $1000) == 0
         if_z           mov      sin, HALF_MAX                                   '    sin = $ffff;
                        
                        jmp      #_waveshape_done


                        '--------------------------------------
                        ' Shape: TRIANGLE
                        '--------------------------------------
_shape_triangle         add     selection_threshold, WAVE_SHAPE_SELECT_THRESH_STEP 
                        cmp     r1, selection_threshold  wc                         
        if_nc           jmp     #_shape_sine                                    ' If shape not set to 'Triangle', jump to 'Sine'

                        '            $0000 $1000 $2000 $3000  
                        '            |     |     |     |
                        '                        
                        '     $FFFF  \           ^           /
                        '             \         / \         /
                        '              \       /   \       /
                        '               \     /     \     /
                        '                \   /       \   /
                        '                 \ /         \ /
                        '     $0000        V           V
                        '                  
                        '
                        mov      r2, angle_16
                        and      r2, ANGLE_180_minus_1
                        shl      r2, #4
                        
                        test     angle_16,ANGLE_180 wz                          ' if ( angle_16 & $1000) == 0

                        'DECREASING portion of triangle wave
         if_z           mov      sin, HALF_MAX
         if_z           sub      sin, r2  

                        'INCREASING portion of triangle wave
         if_nz          mov      sin, r2                       
                        jmp      #_waveshape_done
                        
                        
                        '--------------------------------------
                        ' Shape: SINE
                        '--------------------------------------
_shape_sine
                        '            $0000 $1000 $2000 $3000  
                        '            |     |     |     |
                        '                        
                        '     $FFFF  -           -           -
                        '              \       /   \       /
                        '               |     |     |     | 
                        '               |     |     |     |
                        '               |     |     |     |
                        '                \   /       \   /
                        '     $0000        -           -
                        '                  
                        ' NOTE: The wave shape is "sinusoidal", but is actually calculated as the cosine so that the peak
                        '       magnitude occurs at an angle of 0 which is the most useful phase for tap tempo syncronization.
                  

                        mov     sin, angle_16                                   ' Get 16 bit integer angle (where $1fff = 360 degrees)                                       
                        call    #_getcos                                        ' Get the cos of the angle (returned in sin, as a signed value)
                        add     sin, HALF_MAX                                   ' Convert result to a 17 bit positive integer
                        shr     sin, #1                                         ' Shift result one bit to get a 16 bit positive integer
                       
_waveshape_done
                        '--------------------------------------
                        ' Apply DEPTH
                        '--------------------------------------

                        ' The depth setting "attenuates" the depth of the LFO signal.  The desired behavior is that at a depth of
                        ' zero the LFO will "flat line" at full-signal ($7fffffff), and that at as depth increases the LFO signal range grows larger and larger
                        ' until at 100% it is peaking at full-signal ($7fffffff) and hitting a min at zero.
                        '
                        ' The depth scaling is accomplished by first inverting the LFO, then scaling it by the depth, then inverting it again.
                        '    LFO = MAX_VALUE-((MAX_VALUE-LFO) * Depth)
                         
                        mov     x, HALF_MAX
                        sub     x, sin                                          ' x = $ffff - sin
                        rdlong  y, p_socket_depth                               ' y = *p_socket_depth;
                        shr     y, #16                                          ' y >>= 16;                  
                        call    #_mult                                          ' y = y * x;
                        mov     x, CONTROL_SOCKET_MAX_VALUE                     ' x = $7fffffff
                        sub     x, y                                            ' x = x - y

                        '--------------------------------------
                        ' Output LFO
                        '--------------------------------------
                        wrlong  x, p_socket_lfo

                        '--------------------------------------
                        ' Output "Blink Rate" pulses
                        '--------------------------------------

                        'If angle is rolling over the 360 degree mark, then reinitialize the blink counter.
                        mov     r1, old_angle_16
                        xor     r1, angle_16  
                        test    r1, ANGLE_360    wz
                if_z    jmp     #_edge_detect_done
                        mov     blink_counter, BLINK_ON_TIME
                                               
_edge_detect_done       'If blink count is nonzero, then output "TRUE" (i.e. max scoket value) to "Rate Blink" socket and decrement the counter
                        cmp     blink_counter, #0 wz
                if_nz   wrlong  CONTROL_SOCKET_MAX_VALUE, p_socket_rate_blink
                if_nz   sub     blink_counter, #1

                        'Else if blink count is zero, then output "FALSE" (i.e. 0) to "Rate Blink" socket
                if_z    wrlong  blink_counter, p_socket_rate_blink


                        '--------------------------------------
                        'Done LFO
                        '--------------------------------------
                        jmp     #_frame_sync

'------------------------------------ 
' Get sine/cosine
'
'       quadrant:    1            2            3            4
'          angle:    $0000..$07FF $0800..$0FFF $1000..$17FF $1800..$1FFF
'    table index:    $0000..$07FF $0800..$0001 $0000..$07FF $0800..$0001
'         mirror:    +offset      -offset      +offset      -offset
'           flip:    +sample      +sample      -sample      -sample
'
' on entry: sin[12..0] holds angle (0° to just under 360°)
' on exit: sin holds signed value ranging from $0000FFFF ('1') to
' $FFFF0001 ('-1')
'------------------------------------ 
_getcos                 add     sin,ANGLE_90    'for cosine, add 90°
_getsin                 test    sin,ANGLE_90 wc 'get quadrant 2|4 into c
                        test    sin,ANGLE_180 wz 'get quadrant 3|4 into nz
                        negc    sin,sin         'if quadrant 2|4, negate offset
                        or      sin,sin_table   'or in sin table address >> 1
                        shl     sin,#1          'shift left to get final word address
                        rdword  sin,sin         'read word sample from $E000 to $F000
                        negnz   sin,sin         'if quadrant 3|4, negate sample
_getsin_ret
_getcos_ret             ret                     '39..54 clocks
                                                '(variance due to HUB sync on RDWORD)
ANGLE_90                long    $0800           '90 degrees
ANGLE_180               long    $1000           '180 degrees
ANGLE_180_minus_1       long    $0fff           '180 degrees - 1 angle unit
ANGLE_360               long    $2000           '360 degrees
sin_table               long    $E000 >> 1      'sine table base shifted right
sin                     long    0                                                

'------------------------------------
'16x16 Multiply                                    
'------------------------------------
' Multiply x[15..0] by y[15..0] (y[31..16] must be 0)
' on exit, product in y[31..0]
'------------------------------------
_mult                   shl x,#16               'get multiplicand into x[31..16]
                        mov t,#16               'ready for 16 multiplier bits
                        shr y,#1 wc             'get initial multiplier bit into c
                        
_mult_loop              if_c add y,x wc         'conditionally add multiplicand into product
                        rcr y,#1 wc             'get next multiplier bit into c.
                                                ' while shift product
                        djnz t,#_mult_loop      'loop until done
_mult_ret               ret                     'return with product in y[31..0] 

'------------------------------------
'19-Bit Divide (19 bit quotient, 13 bit denominator)
'------------------------------------
' Divide x[31..0] by y[12..0] (y[13] must be 0)
' on exit, quotient is in x[18..0] and remainder is in x[31..19]
'------------------------------------  
_div19                  shl y,#18               'get divisor into y[30..18]
                        mov t,#19               'ready for 19 quotient bits
                        
_div19_loop             cmpsub x,y wc           'if y =< x then subtract it, set C
                        rcl x,#1                'rotate c into quotient, shift dividend 
                        djnz t,#_div19_loop     'loop until done
                        
_div19_ret              ret                     'quotient in x[18..0], rem. in x[31..19]


'------------------------------------
'16-Bit Divide (16 bit quotient, 16 bit denominator)
'------------------------------------
' Divide x[31..0] by y[15..0] (y[16] must be 0)
' on exit, quotient is in x[15..0] and remainder is in x[31..16]    
'------------------------------------
_div16                  shl y,#15               'get divisor into y[30..15]
                        mov t,#16               'ready for 16 quotient bits
                        
_div16_loop             cmpsub x,y wc           'if y =< x then subtract it, set C
                        rcl x,#1                'rotate c into quotient, shift dividend
                        djnz t,#_div16_loop     'loop until done
                        
_div16_ret              ret                     'quotient in x[15..0], rem. in x[31..16]

'------------------------------------
'Initialized Data                                      
'------------------------------------
LFO_PERIOD_RANGE            long  LFO_PERIOD_MAX_MSEC -  LFO_PERIOD_MIN_MSEC
LFO_CALCULATION_NUMERATOR   long  $00BA2E8B
                                  'NOTE: This value is equavalent to the calculation: hw#MSEC_PER_SEC * hw#ANG_360 * hw#INT_TO_FXP_16_16 / hw#AUDIO_SAMPLE_RATE,
                                  '      but the IDE compiler does not have sufficient numerical resolution to evaluate it without overflowing, so it
                                  '      has been expressed as a pre-evaluated constant.

CONTROL_SOCKET_MAX_VALUE    long  hw#CONTROL_SOCKET_MAX_VALUE
NEGATIVE_ONE                long  $ffffffff
HALF_MAX                    long  $0000FFFF
QUOTIENT_MASK_19            long  $0007ffff        'Divide returns 19 bit quotient
QUOTIENT_MASK_16            long  $0000ffff        'Divide returns 16 bit quotient     
SIGNAL_TRUE                 long  $40000000        'True/False threshold of socket values
SIGN_BIT                    long  $80000000

WAVE_SHAPE_SELECT_THRESH_STEP long   $7fffffff / NUM_WAVE_SHAPES  'Cutoff threshold for wave shape selection                       

BLINK_ON_TIME               long  ((hw#AUDIO_SAMPLE_RATE)/10)  ' On time (in samples) of "Rate Blink" output

'------------------------------------
'Module End                                      
'------------------------------------

'NOTE:  This label is used in the module descriptor data table to calculate the total length of the module's code.
'       It is critical that this label appear AFTER all initialized data, otherwise some initialized data will be
'       lost when modules are saved/restored in OpenStomp Workbench, or converted into Dynamic modules.
_module_end                 long   0

'------------------------------------
'Uninitialized Data
'------------------------------------
                          
r1                        res     1             ' General purpose register
r2                        res     1             ' General purpose register

angle_16_16_fxp           res     1             ' Fixed point 16.16 angle (used for LFO rate calculation)
angle_16                  res     1             ' Integer 16 bit angle
old_angle_16              res     1             ' Previous 16 bit angle

selection_threshold       res     1             ' Wave shape selection threshold value

x                         res     1             ' Used for multiply and divide operations
y                         res     1             ' Used for multiply and divide operations  
t                         res     1             ' Used for multiply and divide operations  

p_system_state_block      res     1             ' Pointer to System State block
p_module_control_block    res     1             ' Pointer to Module Control block
p_ss_overrun_detect       res     1             ' Pointer to Overrun Detect field in the System State block
p_ss_frame_counter        res     1             ' Pointer to the frame counter

p_socket_rate             res     1             ' Pointer to rate socket
p_socket_tap              res     1             ' Pointer to tap socket
p_socket_tap_multiple     res     1             ' Pointer to tap multiple socket 
p_socket_depth            res     1             ' Pointer to depth socket
p_socket_shape            res     1             ' Pointer to shape socket
p_socket_bypass           res     1             ' Pointer to bypass socket
p_socket_lfo              res     1             ' Pointer to LFO socket
p_socket_on               res     1             ' Pointer to on socket
p_socket_rate_blink       res     1             ' Pointer to Rate Blink socket

previous_microframe       res     1             ' Value of the previous microframe counter
current_microframe        res     1             ' Value of the current microframe counter

blink_counter             res     1             ' Counter for the "Rate Blink" output's "On" time

tap_interval              res     1             ' Measures the interval (in samples) between taps of the "+TAP" input
previous_tap              res     1             ' Retains the previous state of the "+TAP" input (for edge detection)
previous_rate             res     1             ' Retains the previous state of the "RATE" input (to detect rate changes)
rate_step_16_16_fxp       res     1             ' The angular LFO rate step, per sample, in 16.16 fixed point.

                          fit                 