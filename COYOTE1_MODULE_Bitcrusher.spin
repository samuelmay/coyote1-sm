''=======================================================================  
'' TITLE: COYOTE1_MODULE_Bitcrusher.spin
''
'' DESCRIPTION:
''   A filtered bit crusher effect by Sam May
''   Visit http://www.samuelmay.id.au for more crazy projects.
''
''   INPUTS:
''     GATE          Input gain/gate control.
''     BITS          Number of bits to crush to. Range from 2 - 16. 
''     FILTER        Not yet implemented. To control some filter parameter for funky sounds.
''     +BYPASS       Effect bypass control
''   OUTPUTS
''     +ON           Set when effect is active (i.e. not bypassed).
'' 
'' COPYRIGHT:
''   Copyright (C)2008 Eric Moyer
''   Copyright (C)2010 Samuel May
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
''  0.0.1  12-03-10  Initial creation.
''  0.0.2  13-03-10  Renamed 'Gain' control to 'Gate' to reflect its function.
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
                        long    $22_40_00_B7                                           'Module Signature
                        long    $00_00_00_02                                           'Module revision  (xx_AA_BB_CC = a.b.c)
                        long    0                                                      'Microframe requirement
                        long    0                                                      'SRAM requirement (heap)
                        long    0                                                      'RAM  requirement (internal propeller RAM)
                        long    0                                                      '(RESERVED0) - set to zero to ensure compatability with future OS versions
                        long    0                                                      '(RESERVED1) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED2) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED3) - set to zero to ensure compatability with future OS versions 
                        long    6                                                      'Number of sockets

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
                        byte    "Gate",0                                         'Socket name  
                        long    2 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    "%",0                                                  'Units  
                        long    0                                                      'Range Low            
                        long    100                                                     'Range High
                        long    50                                                    'Default Value

                        'Socket 3
                        byte    "Bits",0                                               'Socket name  
                        long    3 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0                                                      'Units  
                        long    1                                                      'Range Low            
                        long    16                                                     'Range High
                        long    8                                                      'Default Value

                        'Socket 4
                        byte    "+Bypass",0                                            'Socket name 
                        long    4 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    1                                                      'Default Value

                        'Socket 5
                        byte    "+On",0                                                'Socket name 
                        long    5                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    0                                                      'Default Value

                        byte    "Bit Crusher",0                               'Module name
                        long    hw#NO_SEGMENTATION                                     'Segmentation 

_module_descriptor_end  byte    0    

DAT                                  
'------------------------------------
'Entry
'------------------------------------
                        org
                        
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
                        mov     p_socket_gate,      p_module_control_block
                        add     p_socket_gate,      #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (2 << 2))
                        mov     p_socket_bits,      p_module_control_block
                        add     p_socket_bits,      #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (3 << 2))
                        mov     p_socket_bypass,    p_module_control_block
                        add     p_socket_bypass,    #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (4 << 2)) 
                        mov     p_socket_on,        p_module_control_block
                        add     p_socket_on,        #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (5 << 2))
                        
                        

'------------------------------------
'Effect processing loop
'------------------------------------

                        '------------------------------------
                        'Init
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

                        '-------------------------------------
                        'Get number of bits to crush to
                        '-------------------------------------
                        ' Read control signal value and shift so we have a range of 1-16
                        rdlong  bits,p_socket_bits
                        shr     bits,#28
                        add     bits,#1
                        ' generate a mask for the $bits most significant bits
                        '(excluding sign bit, so the mask will be 0111...) 
                        mov     r1, WORD_NEG
                        shr     r1, #1          ' should be $4000_0000
                        mov     mask,#0
_mask_loop              shr     mask,#1
                        or      mask,r1                          
                        djnz    bits,#_mask_loop
                        
                        '-------------------------------------
                        'Do the crushin'
                        '-------------------------------------
                        ' Read the input gate control, which is really a gain. 
                        rdlong  r1, p_socket_gate
                        'Convert to 16 bit integer                        
                        shr     r1, #15
                        ' "Invert" the integer so that 0 becomes FFFF and FFFF becomes 0.
                        ' This reverses the control knob to the expected direction.            
                        mov     y, WORD_MASK
                        sub     y,r1
                        
                        mov     x, audio_in_sample
                        'Check if sample is negative
                        test    x, WORD_NEG  wc
              if_c      jmp     #_negative       

                        'shr     x, #16          'scale sample for multiplication
                        shr     x, #15          ' apply a bit of boost
                        and     x, WORD_MASK
                        call    #_mult          ' apply gate gain
                        and     y,mask          ' crush bits
                        jmp     #_effect_done

_negative               neg     x, x
                        'shr     x, #16
                        shr     x, #15          ' apply a bit of boost                        
                        and     x, WORD_MASK
                        call    #_mult          ' apply gate gain
                        and     y,mask          ' crush bits
                        neg     y, y                        

_effect_done            wrlong  y,p_socket_audio_out        

                        'Done Echo
                        jmp     #_frame_sync
_loop_forever           jmp     #_loop_forever

'------------------------------------
'Multiply                                    
'------------------------------------
' Multiply x[15..0] by y[15..0] (y[31..16] must be 0)
' on exit, product in y[31..0]
'------------------------------------
_mult                   shl x,#16               'get multiplicand into x[31..16]
                        mov t,#16               'ready for 16 multiplier bits
                        shr y,#1 wc             'get initial multiplier bit into c
_loop
                        if_c add y,x wc         'conditionally add multiplicand into product
                        rcr y,#1 wc             'get next multiplier bit into c.
                                                ' while shift product
                        djnz t,#_loop           'loop until done
_mult_ret               ret

x                       long    $00000000
y                       long    $00000000
t                       long    $00000000

'------------------------------------
'Initialized Data                                      
'------------------------------------
WORD_MASK               long   $0000ffff
WORD_NEG                long   $80000000
SIGNAL_TRUE             long   $40000000

'------------------------------------
'Module End                                      
'------------------------------------

'NOTE:  This label is used in the module descriptor data table to calculate the total length of the module's code.
'       It is critical that this label appear AFTER all initialized data, otherwise some initialized data will be
'       lost when modules are saved/restored in OpenStomp Workbench, or converted into Dynamic modules.
'       This label should appear BEFORE the uninitialized data, otherwise that data will be stored unnecessarily
'       when modules are saved/restored in OpenStomp Workbench, making them larger.
_module_end             long   0

'------------------------------------
'Uninitialized Data
'------------------------------------

r1                        res     1
r2                        res     1

audio_in_sample           res     1

bits                      res     1
mask                      res     1

'' DSP buffers
'input_vector              res     6
'output_vector             res     6

previous_microframe       res     1
current_microframe        res     1

p_module_control_block    res     1
p_system_state_block      res     1
p_frame_counter           res     1
p_ss_overrun_detect       res     1   

p_socket_audio_in         res     1 
p_socket_audio_out        res     1
p_socket_gate             res     1
p_socket_bits             res     1 
p_socket_bypass           res     1 
p_socket_on               res     1

                          fit        