''=======================================================================  
'' TITLE: COYOTE1_DIAGNOSTIC_Audio.spin        
''
'' DESCRIPTION:
''      This is an audio driver used for manufacturing loopback diagnstics.
''   It gernates a sinusoidal tone on the requested output port and
''   monitors the incoming sinal on the requested input port for
''   correlation against a phase shifted version of the output signal
''   to compensate for phase delay in the loop back path.
''      By interpreting the calculated correlation error the diagnostics
''   in the main OS module are able to determine whether the loop back
''   path is connected and passing good data, or malfunctioning in
''   some way.
''
'' COPYRIGHT:
''   Copyright (C)2008 Eric Moyer
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
''  Rev    Date      Description
''  -----  --------  ---------------------------------------------------
''  1.0.0  10-13-08  Initial Release.
''
''======================================================================= 

CON

  ' Audio oscillator definitions
  OSC_FREQ_HZ                 = 400
  ERROR_SAMPLE_WINDOW         = 5000

  FLAG_IN_L                   = 1
  FLAG_OUT_L                  = 2

  ' Audio sample capture states
  STATE_INIT     = 0
  STATE_FIND_LOW = 1
  STATE_FIND_POS = 2
  STATE_CAPTURE  = 3 
  STATE_DONE     = 4
  STATE_IDLE     = 5

  NUM_CAPTURE_SAMPLES    = 244
  SAMPLE_SKIP_COUNT_INIT = 1      'The number of 44khz samples skipped between each sample recorded
  
VAR

  byte audio_cog
  
OBJ
  hw        :       "COYOTE1_HW_Definitions.spin"  'Hardware definitions        


PUB start (audio_diag_control_block_p)

  audio_cog := cognew(@_module_entry, audio_diag_control_block_p)

PUB stop

  cogstop(audio_cog)
  
DAT
                        
'------------------------------------
'Module Code
'------------------------------------
                        org
                        
_module_entry
                        mov     p_audio_diag_ctl_block, PAR                       'Get pointer to Audio Diag Control Block

                        rdlong  p_system_state_block,p_audio_diag_ctl_block       'Get pointer to System State Block

                        mov     p_error_count,p_audio_diag_ctl_block              'Get pointer to error count
                        add     p_error_count, #4
                        mov     p_phase_adjust,p_audio_diag_ctl_block             'Get pointer to phase adjustment
                        add     p_phase_adjust, #8                  
                        mov     p_flags,p_audio_diag_ctl_block                    'Get pointer to control flags
                        add     p_flags, #12
                        
                        mov     r1 ,p_audio_diag_ctl_block                        'Get pointer to Left capture buffer
                        add     r1, #16
                        rdlong  p_cap_l_buffer, r1
                        add     r1, #4
                        rdlong  p_cap_r_buffer, r1  

                        mov     p_gain_shift,p_audio_diag_ctl_block               'Get pointer to gain shift
                        add     p_gain_shift, #24
                          
                        mov     p_frame_counter,    p_system_state_block
                        mov     p_audio_out_left,   p_system_state_block
                        add     p_audio_out_left,   #(hw#SS_OFFSET__OUT_LEFT)
                        mov     p_audio_out_right,  p_system_state_block
                        add     p_audio_out_right,  #(hw#SS_OFFSET__OUT_RIGHT)
                        mov     p_audio_in_left,    p_system_state_block
                        add     p_audio_in_left,    #(hw#SS_OFFSET__IN_LEFT)
                        mov     p_audio_in_right,   p_system_state_block
                        add     p_audio_in_right,   #(hw#SS_OFFSET__IN_RIGHT)
                        
                        
'------------------------------------
'Audio processing loop
'------------------------------------

                        '------------------------------------
                        'Init
                        '------------------------------------ 
                        mov     angle_16_16_fxp, #0
                        mov     error_samples, ERROR_SAMPLE_WINDOW_C
                        mov     correlation_error, #0
                        mov     cap_l_state, #STATE_INIT
                        mov     cap_r_state, #STATE_INIT

                        '------------------------------------
                        'Sync
                        '------------------------------------
                        rdlong  previous_microframe, p_frame_counter            'Initialize previous microframe
                        
                        'Wait for the beginning of a new microframe
_frame_sync             rdlong  current_microframe, p_frame_counter
                        cmp     previous_microframe, current_microframe  wz
              if_z      jmp     #_frame_sync                                    'If current_microframe = previoius_microframe
                        mov     previous_microframe, current_microframe         'previous_microframe = current_microframe 
                        
                        '------------------------------------
                        'Audio frequency oscillator
                        '------------------------------------

                        add     angle_16_16_fxp, OSC_STEP_FXP_16_16
                        mov     sin, angle_16_16_fxp
                        shr     sin, #16                                         'Convert from 16.16 fixed point angle to integer angle (where $1fff = 360 degrees)
                        call    #_getsin

                        shl     sin, #14                                         'Output at 1/2 max amplitude

                        '------------------------------------
                        'Output Audio
                        '------------------------------------
                        rdlong  flags, p_flags
                        test    flags, #FLAG_OUT_L   wz
               if_nz    wrlong  sin, p_audio_out_left
               if_z     wrlong  sin, p_audio_out_right

                        '------------------------------------
                        'Calculate correlation reference
                        '------------------------------------
                        mov    sin, angle_16_16_fxp
                        shr    sin, #16
                        rdlong r2, p_phase_adjust
                        add    sin, r2
                        call   #_getsin
                        shl    sin, #14                                          'Output at 1/2 max amplitude 
                        
                        '------------------------------------
                        'Measure loopback correlation
                        '------------------------------------
                        rdlong  gain_shift, p_gain_shift   
                        test    flags, #FLAG_IN_L    wz  
               if_nz    rdlong  r1, p_audio_in_left
               if_z     rdlong  r1, p_audio_in_right                                
               if_z     shl     r1, #1
                        shl     r1, gain_shift  
                        sar     sin, #16
                        sar     r1, #16
                        sub     r1, sin
                        abs     r1, r1
                        add     correlation_error, r1

                        djnz    error_samples, #_skip
                        wrlong  correlation_error, p_error_count
                        mov     error_samples, ERROR_SAMPLE_WINDOW_C
                        mov     correlation_error, #0
_skip
                        '------------------------------------
                        'Capture Left
                        '------------------------------------
                        rdlong  sample, p_audio_in_left                            'Read sample
                        shl     sample, gain_shift

                        'State: INIT
                        cmp     cap_l_state, #STATE_INIT      wz
              if_z      mov     p_cap_l_current, p_cap_l_buffer
              if_z      mov     cap_l_count, #NUM_CAPTURE_SAMPLES
              if_z      mov     cap_l_skip_count, #SAMPLE_SKIP_COUNT_INIT
              if_z      mov     cap_l_state, #STATE_FIND_LOW

                        'State: FIND LOW
                        cmp     cap_l_state, #STATE_FIND_LOW  wz
              if_nz     jmp     #_l_find_positive          
                        cmps    sample, #0                    wc
              if_c      mov     cap_l_state, #STATE_FIND_POS
              
                        'State: FIND POSITIVE
_l_find_positive        cmp     cap_l_state, #STATE_FIND_POS  wz
              if_nz     jmp     #_l_capture                
                        cmps    sample, #0                    wc
              if_nc     mov     cap_l_state, #STATE_CAPTURE 

                        'State: CAPTURE
_l_capture              cmp     cap_l_state, #STATE_CAPTURE   wz
              if_nz     jmp     #_l_capture_done
                        djnz    cap_l_skip_count, #_l_capture_done
                        mov     cap_l_skip_count, #SAMPLE_SKIP_COUNT_INIT 
                        
                        wrlong  sample, p_cap_l_current
                        add     p_cap_l_current, #4
                        sub     cap_l_count, #1               wz
              if_z      mov     cap_l_state, #STATE_INIT

_l_capture_done

                        '------------------------------------
                        'Capture Right
                        '------------------------------------
                        rdlong  sample, p_audio_in_right                        'Read sample
                        shl     sample, gain_shift

                        'State: INIT
                        cmp     cap_r_state, #STATE_INIT      wz
              if_z      mov     p_cap_r_current, p_cap_r_buffer
              if_z      mov     cap_r_count, #NUM_CAPTURE_SAMPLES
              if_z      mov     cap_r_skip_count, #SAMPLE_SKIP_COUNT_INIT
              if_z      mov     cap_r_state, #STATE_FIND_LOW

                        'State: FIND LOW
                        cmp     cap_r_state, #STATE_FIND_LOW  wz
              if_nz     jmp     #_r_find_positive          
                        cmps    sample, #0                    wc
              if_c      mov     cap_r_state, #STATE_FIND_POS
              
                        'State: FIND POSITIVE
_r_find_positive        cmp     cap_r_state, #STATE_FIND_POS  wz
              if_nz     jmp     #_r_capture                
                        cmps    sample, #0                    wc
              if_nc     mov     cap_r_state, #STATE_CAPTURE 

                        'State: CAPTURE
_r_capture              cmp     cap_r_state, #STATE_CAPTURE   wz
              if_nz     jmp     #_r_capture_done
                        djnz    cap_r_skip_count, #_r_capture_done
                        mov     cap_r_skip_count, #SAMPLE_SKIP_COUNT_INIT 
                        
                        wrlong  sample, p_cap_r_current
                        add     p_cap_r_current, #4
                        sub     cap_r_count, #1               wz
              if_z      mov     cap_r_state, #STATE_INIT

_r_capture_done


 
                        jmp     #_frame_sync

'------------------------------------
'Get sine/cosine                                    
'------------------------------------
' 
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
_getcos                 add     sin,sin_90      'for cosine, add 90°
_getsin                 test    sin,sin_90 wc   'get quadrant 2|4 into c
                        test    sin,sin_180 wz  'get quadrant 3|4 into nz
                        negc    sin,sin         'if quadrant 2|4, negate offset
                        or      sin,sin_table   'or in sin table address >> 1
                        shl     sin,#1          'shift left to get final word address
                        rdword  sin,sin         'read word sample from $E000 to $F000
                        negnz   sin,sin         'if quadrant 3|4, negate sample
_getsin_ret
_getcos_ret             ret                     '39..54 clocks
                                                '(variance due to HUB sync on RDWORD)

sin_90                  long    $0800
sin_180                 long    $1000
sin_table               long    $E000 >> 1      'sine table base shifted right
sin                     long    0



'------------------------------------
'Initialized Data                                      
'------------------------------------
OSC_STEP_FXP_16_16      long  OSC_FREQ_HZ * (hw#ANG_360 * hw#INT_TO_FXP_16_16 / hw#AUDIO_SAMPLE_RATE)
ERROR_SAMPLE_WINDOW_C   long  ERROR_SAMPLE_WINDOW

'------------------------------------
'Uninitialized Data
'------------------------------------                          
r1                        res     1
r2                        res     1
flags                     res     1
angle_16_16_fxp           res     1
gain_shift                res     1

p_system_state_block      res     1
p_audio_diag_ctl_block    res     1
p_phase_adjust            res     1
previous_microframe       res     1
current_microframe        res     1  

p_frame_counter           res     1
p_audio_out_left          res     1
p_audio_out_right         res     1
p_audio_in_left           res     1
p_audio_in_right          res     1
p_error_count             res     1
p_flags                   res     1
p_gain_shift              res     1

error_samples             res     1
correlation_error         res     1


'Capture engine
sample                    res     1

cap_l_state               res     1
cap_l_count               res     1
cap_l_skip_count          res     1     
p_cap_l_current           res     1
p_cap_l_buffer            res     1

cap_r_state               res     1
cap_r_count               res     1
cap_r_skip_count          res     1  
p_cap_r_current           res     1
p_cap_r_buffer            res     1

                          fit                 