''=======================================================================  
'' TITLE: COYOTE1_MODULE_Octavepus.spin
''
'' DESCRIPTION:
''
''   An octave shifter based on an analogue full-wave rectifier design.
''
''   INPUTS:
''      IN:           Audio In
''      +BYPASS:      Effect bypass control
''
''   OUTPUTS:
''      OUT:          Audio Out
''      +ON:          Set when effect is active (i.e. not bypassed).
''
'' COPYRIGHT:
''   Copyright (C)2009 Eric Moyer, (C) 2010 Sam May
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
''  0.0.1  18-03-10  Initial release.
''
''=======================================================================  

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
                        long    $23_40_00_B7                                           'Module Signature
                        long    $00_00_00_01                                           'Module revision  (xx_AA_BB_CC = a.b.c)
                        long    0                                                      'Microframe requirement
                        long    0                                                      'SRAM requirement (heap)  
                        long    0                                                      'RAM  requirement (internal propeller RAM)
                        long    0                                                      '(RESERVED0) - set to zero to ensure compatability with future OS versions
                        long    0                                                      '(RESERVED1) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED2) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED3) - set to zero to ensure compatability with future OS versions 
                        long    4                                                      'Number of sockets

                        'Socket 0
                        byte    "In",0                                                 'Socket name  
                        long    0 | hw#SOCKET_FLAG__SIGNAL | hw#SOCKET_FLAG__INPUT     'Socket flags and ID
                        byte    0  {null string}                                       'Units  
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value

                        'Socket 1
                        byte    "Out",0                                                'Socket name   
                        long    1 | hw#SOCKET_FLAG__SIGNAL                             'Socket flags and ID
                        byte    0  {null string}                                       'Units  
                        long    0                                                      'Range Low          
                        long    0                                                      'Range High         
                        long    0                                                      'Default Value
                        
                        'Socket 2
                        byte    "+Bypass",0                                            'Socket name 
                        long    2 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    0                                                      'Default Value

                        'Socket 3
                        byte    "+On",0                                                'Socket name 
                        long    3                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    1                                                      'Default Value

                        byte    "Octavepus",0                                    'Module name
                        long    hw#NO_SEGMENTATION                                     'Segmentation 

_module_descriptor_end  byte    0


DAT
                        
'------------------------------------
'Entry
'------------------------------------
                        org     0
                        
_module_entry
                        mov     p_module_control_block, PAR                     'Get pointer to Module Control Block
                        rdlong  p_system_state_block, p_module_control_block    'Get pointer to System State Block

                        'Initialize pointers into System State block
                        mov     p_frame_counter,    p_system_state_block
                        mov     p_ss_overrun_detect,p_system_state_block
                        add     p_ss_overrun_detect,#(hw#SS_OFFSET__OVERRUN_DETECT)
                        
                        mov     p_socket_audio_in,  p_module_control_block
                        add     p_socket_audio_in,  #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (0 << 2))
                        mov     p_socket_audio_out, p_module_control_block
                        add     p_socket_audio_out, #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (1 << 2))
                        mov     p_socket_bypass,    p_module_control_block               
                        add     p_socket_bypass,    #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (2 << 2)) 
                        mov     p_socket_on,        p_module_control_block
                        add     p_socket_on,        #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (3 << 2)) 
                        

                        '------------------------------------
                        'Init
                        '------------------------------------

                        
'------------------------------------
'Effect processing loop
'------------------------------------

                        '------------------------------------
                        'Sync
                        '------------------------------------
                        rdlong  previous_microframe, p_frame_counter            'Initialize previous microframe
                        
                        'Wait for the beginning of a new microframe
_frame_sync             rdlong  current_microframe, p_frame_counter
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
                        'Get audio in sample
                        '------------------------------------
                        rdlong  audio_in_sample, p_socket_audio_in   
                        
                        '------------------------------------
                        'Bypass
                        '------------------------------------
                        'Read bypass state
                        rdlong  r1, p_socket_bypass  
                        cmp     SIGNAL_TRUE, r1   wc, wz

                        'Update on/off indication
        if_c_or_z       mov     r2, 0
        if_nc_and_nz    mov     r2, SIGNAL_TRUE
                        wrlong  r2, p_socket_on
                        
                        'If bypassed, then just pass audio through
        if_c_or_z       wrlong  audio_in_sample, p_socket_audio_out
        if_c_or_z       jmp     #_frame_sync

                        '------------------------------------
                        'Effect
                        '------------------------------------   
                        '' Rectify input wave
                        abs     x,audio_in_sample
                        '' Filter out the DC. The signal is now an
                        '' AC waveform at twice the original frequency.
                        call    #_dcblock
                        '' Normalize output volume.
                        shl     y,#1
                        '' Mask out least significant bits to minimize noise.
                        andn    y,WORD_MASK
                        '' And we're done. That was easy!
                        wrlong  y,p_socket_audio_out

                        'Done Echo
                        jmp     #_frame_sync
_loop_forever           jmp     #_loop_forever

'------------------------------------
'Signed multiply                                    
'------------------------------------
''' Multiply integer part of 16.16 fixed point in m1 (31..16) by the fractional
''' part of 16.16 fixed point in m2 (15..0).
''' 
''' On exit, 16.16 fixed point product in m2.
''' 
''' m1 may be signed. m2 CANNOT be signed.
'''
''' Takes 36 instructions, 30% faster than the stock _mult.
        
'------------------------------------
_mults
                andn    m1,WORD_MASK
                and     m2,WORD_MASK
                sar     m2,#1   wc '1st bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '2nd bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '3rd bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '4th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '5th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '6th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '7th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '8th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '9th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '10th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '11th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '12th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '13th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '14th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '15th bit
        if_c    adds    m2,m1
                sar     m2,#1   wc '16th bit
        if_c    adds    m2,m1
                sar     m2,#1   'shift final result into place
_mults_ret      ret

m1                       long    $00000000
m2                       long    $00000000

'------------------------------------
'DC-blocking Filter
'------------------------------------
''' See https://ccrma.stanford.edu/~jos/filters/DC_Blocker.html
'''
''' Basically a specialised high-pass filter. Difference equation is
'''
'''   y[n] = x[n] - x[n-1] + R * y[n-1]
'''
''' where R is typically between 0.9 and 1. Higher R gives better DC blocking,
''' but slower tracking of varying DC. We will use 0.99 or 0.FD71.
_dcblock
                mov     y,x             'accumulate output value in y
                subs    y,x1            'subtract x[n-1]

                mov     m1,y1
                mov     m2,R
                call    #_mults         'evaluate R * y[n-1]
                adds    y,m2            'add R * y[n-1]
                
                mov     x1,x            'update registers for next call
                mov     y1,y
_dcblock_ret    ret

x       long    $00000000
x1      long    $00000000
y       long    $00000000
y1      long    $00000000
'Useful values: E667 = 0.90, EB86 = 0.92, F0A4 = 0.94, F5C3 = 0.96,
'FAE1 = 0.98,FD71 = 0.99
R       long    $0000E667

'------------------------------------
'Low Pass Filter                                      
'------------------------------------
''' TODO

'------------------------------------
'Initialized Data                                      
'------------------------------------
SIGN_BIT                long   $80000000
SIGNAL_TRUE             long   $40000000
WORD_MASK               long   $0000FFFF
KNOB_POSITION_MAX       long   hw#KNOB_POSITION_MAX

'------------------------------------
'Module End                                      
'------------------------------------

'NOTE:  This label is used in the module descriptor data table to calculate the total length of the module's code.
'       It is critical that this label appear AFTER all initialized data, otherwise some initialized data will be
'       lost when modules are saved/restored in OpenStomp Workbench, or converted into Dynamic modules.
_module_end             long   0

'------------------------------------
'Uninitialized Data
'------------------------------------

r1                        res     1
r2                        res     1

audio_in_sample           res     1

p_system_state_block      res     1
p_module_control_block    res     1
p_ss_overrun_detect       res     1
previous_microframe       res     1
current_microframe        res     1 
p_frame_counter           res     1

p_socket_audio_in         res     1 
p_socket_audio_out        res     1 
p_socket_bypass           res     1 
p_socket_on               res     1

                          fit
        