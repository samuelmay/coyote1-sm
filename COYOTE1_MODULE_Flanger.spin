''=======================================================================  
'' TITLE: COYOTE1_MODULE_Flanger.spin
''
'' DESCRIPTION:
''   A flanger effect by Samuel May <sam.m4y@gmail.com>.
''   Visit http://www.samuelmay.id.au for more crazy projects.
''
''   INPUTS:
''     LFO           Input for external LFO module that controls the magnitude
''                   of the delay.
''     DEPTH         Controls the prominance or depth of the flanging effect.
''     MODE          Select 'feedforward' or 'feedback' mode. Feedforward mode
''                   produces traditional, subtle analog flanging; feedback
''                   mode produces a wilder synthy effect.
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
''  0.0.1  08-03-10  Initial creation.
''  0.0.2  12-03-10  Modified to use external LFO module.
''  0.0.3  22-03-10  Implemented linear interpolating delay.
''  0.0.4  22-03-10  Added 'Regen' feedback comb control.
''  0.0.5  24-03-10  Change to one depth control and a mode selection control. 
''
''=======================================================================  
''
'' Notes:
''    The max value of an input control socket is $7FFF_FFFF.
''
''    Invaluable resources for developing this module (as well as
''    understanding flangers in general) have been:
''
''    http://www.spinsemi.com/knowledge_base/effects.html
''    https://ccrma.stanford.edu/~jos/pasp/Flanging.html
''    https://ccrma.stanford.edu/~jos/pasp/Linear_Interpolation.html
''
''=======================================================================  
CON
  'Heap requirement for 70 samples. Not this many will be used, but rounded
  'up for convienience. We'll need 64 for the biggest sweep, +1 for
  'interpolation, plus 3 or 4 for the constant offset.
  C_SRAM_BUFFER_SIZE           = 210
  'Bytes per SRAM sample                                               
  C_SRAM_SAMPLE_SIZE           = 3
  
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
                        long    $02_00_00_B7                                           'Module Signature
                        long    $00_00_00_05                                           'Module revision  (xx_AA_BB_CC = a.b.c)
                        long    0                                                      'Microframe requirement
                        long    C_SRAM_BUFFER_SIZE + 4                                 'SRAM requirement (heap)
                        long    0                                                      'RAM  requirement (internal propeller RAM)
                        long    0                                                      '(RESERVED0) - set to zero to ensure compatability with future OS versions
                        long    0                                                      '(RESERVED1) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED2) - set to zero to ensure compatability with future OS versions 
                        long    0                                                      '(RESERVED3) - set to zero to ensure compatability with future OS versions 
                        long    7                                                      'Number of sockets

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
                        byte    "LFO",0                                                'Socket name  
                        long    2 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0                                                      'Units  
                        long    0                                                      'Range Low            
                        long    0                                                      'Range High
                        long    0                                                      'Default Value

                        'Socket 3
                        byte    "Depth",0                                              'Socket name  
                        long    3 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    "%",0                                                  'Units  
                        long    0                                                      'Range Low            
                        long    100                                                    'Range High
                        long    100                                                    'Default Value

                        'Socket 4
                        byte    "Mode",0                                               'Socket name  
                        long    4 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0                                                      'Units  
                        long    0                                                      'Range Low            
                        long    1                                                      'Range High
                        long    0                                                      'Default Value

                        'Socket 5
                        byte    "+Bypass",0                                            'Socket name 
                        long    5 | hw#SOCKET_FLAG__INPUT                              'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    1                                                      'Default Value

                        'Socket 6
                        byte    "+On",0                                                'Socket name 
                        long    6                                                      'Socket flags and ID
                        byte    0  {null string}                                       'Units   
                        long    0                                                      'Range Low          
                        long    1                                                      'Range High         
                        long    0                                                      'Default Value

                        byte    "Flanger",0                                              'Module name
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
                        mov     r1,                 p_module_control_block
                        add     r1,                 #(hw#MCB_OFFSET__HEAP_BASE_P)
                        rdlong  heap_base_address, r1
                        
                        mov     p_socket_audio_in,  p_module_control_block
                        add     p_socket_audio_in,  #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (0 << 2))
                        mov     p_socket_audio_out, p_module_control_block
                        add     p_socket_audio_out, #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (1 << 2))
                        mov     p_socket_lfo,       p_module_control_block
                        add     p_socket_lfo,       #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (2 << 2))
                        mov     p_socket_depth,     p_module_control_block
                        add     p_socket_depth,     #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (3 << 2))
                        mov     p_socket_mode,      p_module_control_block
                        add     p_socket_mode,      #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (4 << 2))                        
                        mov     p_socket_bypass,    p_module_control_block
                        add     p_socket_bypass,    #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (5 << 2)) 
                        mov     p_socket_on,        p_module_control_block
                        add     p_socket_on,        #(hw#MCB_OFFSET__SOCKET_EXCHANGE + (6 << 2))
                        
                        

'------------------------------------
'Effect processing loop
'------------------------------------

                        '------------------------------------
                        'Init
                        '------------------------------------   
                        mov     sram_p_in, heap_base_address
        
                        'Set MEMBUS interface as outputs
                        or       dira, PINGROUP__MEM_INTERFACE
                        or       dira, PIN__LCD_MUX
                        andn     outa, PIN__LCD_MUX

                        '------------------------------------
                        'Clear SRAM
                        '------------------------------------
                        mov     sram_data, #0
                        mov     sram_address, heap_base_address

_lock1                  lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock1
              
                        call    #_sram_write
                        mov     r2, SRAM_BUFFER_SIZE
                                     
_clear_loop             call    #_sram_burst_write
                        sub     r2, #C_SRAM_SAMPLE_SIZE  wc                    
              if_nc     jmp     #_clear_loop
                        lockclr hw#LOCK_ID__MEMBUS  

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
                        'Determine delay amount (in samples) from LFO
                        '------------------------------------
                        '
                        
                        ' Read LFO signal (Max $7FFFFFFF, Min depends on amplitude)
                        rdlong  r1, p_socket_lfo
                        ' invert LFO so that Min is 0 and Max depends on amplitude
                        mov     delay_int,CONTROL_SOCKET_MAX_VALUE
                        sub     delay_int,r1
                        ' extract integer and fractional parts in range 1-64.99
                        ' Fractional part is bottom 16 bits, integer part is top 15 bits. 
                        mov     delay_frac,delay_int
                        shr     delay_frac,#9
                        and     delay_frac,WORD_MASK
                        shr     delay_int,#25
                        ' This is our constant sweep offset. ATTENTION! YOU THE USER COULD TUNE THIS!
                        ' todo: make this an initialization value 
                        'add     delay_int,#1
                        add     delay_int,#4                             
                        ' multiply delay amount by 3 to get pointer
                        mov     r2, delay_int
                        shl     r2, #1
                        add     delay_int, r2
              
                        '------------------------------------
                        'Get first delay sample
                        '------------------------------------
                        mov     sram_p_out, sram_p_in
                        sub     sram_p_out, delay_int          wc       'sram_p_out -= delay
                  if_nc sub     sram_p_out, heap_base_address  wc, nr   'if ((sram_p_out < heap_base_address) || (sram_p_out < 0))               
                  if_c  add     sram_p_out, SRAM_BUFFER_SIZE            '   sram_p_out += SRAM_BUFFER_SIZE
                        
                        'Read delayed value. This could be the current input sample
                        '(once a cycle in fact, when the delay is 0) 
                        mov     sram_address, sram_p_out
_lock2                  lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock2
                        call    #_sram_read
                        lockclr hw#LOCK_ID__MEMBUS

                        mov     delay_sample, sram_data
                        
                        '------------------------------------
                        'Get second delay sample
                        '------------------------------------
                        add     delay_int,#3
                        
                        mov     sram_p_out, sram_p_in
                        sub     sram_p_out, delay_int          wc       'sram_p_out -= delay
                  if_nc sub     sram_p_out, heap_base_address  wc, nr   'if ((sram_p_out < heap_base_address) || (sram_p_out < 0))               
                  if_c  add     sram_p_out, SRAM_BUFFER_SIZE            '   sram_p_out += SRAM_BUFFER_SIZE
 
                        mov     sram_address, sram_p_out
_lock3                  lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock3
                        call    #_sram_read
                        lockclr hw#LOCK_ID__MEMBUS

                        '------------------------------------
                        'Interpolate between delay samples
                        '------------------------------------
                        'equation is
                        '  y[n+d] = y[n] + d * (y[n+1] - y[n])
                        ' where n is delay_int and d is delay_frac
                        mov     m2, delay_frac
                        mov     m1, sram_data
                        subs    m1, delay_sample
                        call    #_mults
                        adds    delay_sample,m2

                        '------------------------------------
                        'Scale delay amplitude according to Depth control
                        '------------------------------------
                        rdlong  m2, p_socket_depth
                        shr     m2, #15                        
                        mov     m1, delay_sample
                        call    #_mults

                        '------------------------------------
                        'Get mode setting
                        '------------------------------------
                        rdlong  r1, p_socket_mode
                        cmp     SIGNAL_TRUE,r1          wc
        if_c            jmp     #_feedback_mode

                        '-------------------------------------
                        'Feedforward
                        '-------------------------------------                        
_feedforward_mode       mov     r1, audio_in_sample
                        adds    r1, m2
                        jmp     #_effect_done
                        
                        '------------------------------------
                        'Feedback
                        '------------------------------------
_feedback_mode          subs    audio_in_sample,m2      ' delay effect will be recirculated
                        mov     r1,audio_in_sample

_effect_done
                        'smooth out noise
                        andn    r1,NOISE_MASK                                                                                
                        'Send to output
                        wrlong  r1, p_socket_audio_out

                        'Save latest sample to sram
                        mov     sram_data, audio_in_sample
                        mov     sram_address, sram_p_in
_lock4                  lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock4
                        call    #_sram_write
                        lockclr hw#LOCK_ID__MEMBUS
                        
                        'Bump SRAM pointer
                        add      sram_p_in, #3
                        mov      r1, heap_base_address
                        add      r1, SRAM_BUFFER_SIZE
                        cmp      r1, sram_p_in  wc
                   if_c mov      sram_p_in, heap_base_address
               
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
'MEMBUS Read
'------------------------------------
_sram_read

                        or      dira, PINGROUP__MEMBUS
                        
                        'Write HIGH address
                        mov     r1, sram_address
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_HIGH

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        'Write MID address
                        mov     r1, sram_address
                        shl     r1, #8
                        and     r1, PINGROUP__MEMBUS   
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_MID

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK
 
                        'Write LOW address
                        mov     r1, sram_address
                        shl     r1, #16
                        and     r1, PINGROUP__MEMBUS   
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_LOW

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        'Setup Read
                        andn    dira, PINGROUP__MEMBUS

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__READ_BYTE

                        'Clear data longword
                        mov     sram_data, #0

                        'Read HIGH byte
                        or      outa, PIN__MEMBUS_CLK
                        mov     sram_data, ina
                        andn    outa, PIN__MEMBUS_CLK
                        and     sram_data, PINGROUP__MEMBUS
                        
                        'Read MID byte
                        or      outa, PIN__MEMBUS_CLK
                        mov     r1, ina
                        andn    outa, PIN__MEMBUS_CLK
                        and     r1, PINGROUP__MEMBUS  
                        shr     r1, #8
                        or      sram_data, r1

                        'Read Low byte
                        or      outa, PIN__MEMBUS_CLK
                        mov     r1, ina
                        andn    outa, PIN__MEMBUS_CLK
                        and     r1, PINGROUP__MEMBUS 
                        shr     r1, #16
                        or      sram_data, r1

                        'convert 24 bit word to 32 bit word
                        shl     sram_data, #8


                        andn    outa, PINGROUP__MEM_INTERFACE
_sram_read_ret          ret
                        
                         
'------------------------------------
'MEMBUS Write
'------------------------------------
_sram_write

                        or      dira, PINGROUP__MEMBUS
                        
                        'Write HIGH address
                        mov     r1, sram_address
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_HIGH

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        'Write MID address
                        mov     r1, sram_address
                        shl     r1, #8
                        and     r1, PINGROUP__MEMBUS  
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_MID

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        'Write LOW address
                        mov     r1, sram_address
                        shl     r1, #16
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS
                        or      outa, r1

                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__SET_ADDR_LOW

                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK
                        
_sram_burst_write
                      
                        'Setup Write
                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__WRITE_BYTE

                        'Write HIGH byte
                        mov     r1, sram_data
                        shr     r1, #8
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS   
                        or      outa, r1
                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK
                        
                        'Write MID byte
                        mov     r1, sram_data
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS   
                        or      outa, r1
                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        'Write Low byte
                        mov     r1, sram_data
                        shl     r1, #8
                        and     r1, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS   
                        or      outa, r1
                        or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK

                        andn    outa, PINGROUP__MEM_INTERFACE
                        andn    dira, PINGROUP__MEMBUS 
_sram_burst_write_ret                        
_sram_write_ret         ret

        
'------------------------------------
'Initialized Data                                      
'------------------------------------

SRAM_BUFFER_SIZE        long   C_SRAM_BUFFER_SIZE

PINGROUP__MEM_INTERFACE long   hw#PINGROUP__MEM_INTERFACE
PINGROUP__MEMBUS        long   hw#PINGROUP__MEMBUS
PINGROUP__MEMBUS_CNTL   long   hw#PINGROUP__MEMBUS_CNTL 
PIN__MEMBUS_CLK         long   hw#PIN__MEMBUS_CLK
PIN__LCD_MUX            long   hw#PIN__LCD_MUX
MID_ADDR_MASK           long   $0000ff00
SIGN_BIT                long   $80000000 
SRAM_END_ADDRESS        long   $0007ffe0
NOISE_MASK              long   $0000ffff
WORD_MASK               long   $0000ffff
WORD_NEG                long   $80000000
SIGNAL_TRUE             long   $40000000

CONTROL_SOCKET_MAX_VALUE    long  hw#CONTROL_SOCKET_MAX_VALUE
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

delay_int                 res     1
delay_frac                res     1
delay_sample              res     1

r1                        res     1
r2                        res     1

sram_address              res     1
sram_data                 res     1

audio_in_sample           res     1

sram_p_in                 res     1
sram_p_out                res     1

previous_microframe       res     1
current_microframe        res     1

p_module_control_block    res     1
p_system_state_block      res     1
heap_base_address         res     1 
p_frame_counter           res     1
p_ss_overrun_detect       res     1   

p_socket_audio_in         res     1 
p_socket_audio_out        res     1
p_socket_lfo              res     1
p_socket_depth            res     1
p_socket_mode             res     1 
p_socket_bypass           res     1 
p_socket_on               res     1

                          fit                 