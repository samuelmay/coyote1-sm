''=======================================================================  
'' TITLE: COYOTE1_Conduit_Engine.SPIN
''
'' DESCRIPTION:
''    Conduit engine.
''
''    This is the workhorse engine which copies data between sockets based on
''    the conduits defined in a patch.  The main portion of the conduit
''    engine (the code which does all the data copiess) is dynamically generated
''    by the OS when a patch is started, and inserted at the label
''    "CONDUIT_engine_splice".
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
''  002  10-19-08  Expand module description comments.
''  003  11-01-08  Update 'Gain' system resource so it's range is 0-100% (as displayed) instead of 0-200% (as it was previously behaving)
''
''=======================================================================

CON
   END_OF_COG_RAM      = $1ef   'The longword address of the last usable longword in COG RAM (the COG Specical Purpose Registers
                                'begin at $1f0).

   'These are the longword memory addresses of the "r1" and "r2" registers used by the conduit engine, which is
   'dynamically generated on-the-fly by the OS module.  The registers are located at the end of usable COG
   'memory
   LW_ADDRESS__r1      = END_OF_COG_RAM - 1             
   LW_ADDRESS__r2      = END_OF_COG_RAM - 2
   
OBJ

   hw          : "COYOTE1_HW_Definitions.spin"  'Hardware definitions

PUB  get_start_address
  return (@CONDUIT_engine_entry)

PUB  get_splice_address
  return (@CONDUIT_engine_splice)

DAT

'===============================================================================================================
'                                                     CONDUIT ENGINE
'===============================================================================================================

                        org     0
CONDUIT_engine_entry
                                    
                        '------------------------------------
                        'Init
                        '------------------------------------
                        mov     p_frame_counter,PAR                            'Get pointer to System State 
                        rdlong  previous_microframe, p_frame_counter           'Initialize previous microframe

                        mov     p_ss_gain_in_socket, PAR    
                        add     p_ss_gain_in_socket,#hw#SS_OFFSET__GAIN_IN_SOCKET    
                        mov     p_ss_gain_out_socket, PAR    
                        add     p_ss_gain_out_socket,#hw#SS_OFFSET__GAIN_OUT_SOCKET
                        mov     p_ss_gain_control_socket, PAR    
                        add     p_ss_gain_control_socket,#hw#SS_OFFSET__GAIN_CONTROL_SOCKET

                        'Place $80000000 (the sign bit) into sign_bit
                        mov     sign_bit, #1
                        shl     sign_bit, #31
                        
                        '------------------------------------
                        'Sync
                        '------------------------------------
                        'Wait for the beginning of a new microframe
frame_sync              rdlong  current_microframe, p_frame_counter
                        cmp     previous_microframe, current_microframe  wz
              if_z      jmp     #frame_sync                                    'If current_microframe = previoius_microframe
                        mov     previous_microframe, current_microframe        'previous_microframe = current_microframe

                        '====================================
                        'Provide GAIN System Resource                               
                        '====================================

                        rdlong  y,p_ss_gain_control_socket
                        shr     y,#15
                        rdlong  x,p_ss_gain_in_socket

                        'Signed multiply y<32> = (x<16> * y<16>)
                        test    x, sign_bit  wz
                 if_nz  neg     x, x
                        shr     x, #16
                        call    #mult
                 if_nz  neg     y, y

:mult_done              wrlong  y,p_ss_gain_out_socket

                        '------------------------------------
                        'Process conduits
                        '------------------------------------
                        'Jump past the "mult" code and the data registers
                        jmp     #CONDUIT_engine_splice


'------------------------------------
'Multiply                                    
'------------------------------------
' Multiply x[15..0] by y[15..0] (y[31..16] must be 0)
' on exit, product in y[31..0]
'------------------------------------
mult                    shl x,#16               'get multiplicand into x[31..16]
                        mov t,#16               'ready for 16 multiplier bits
                        shr y,#1 wc             'get initial multiplier bit into c
:loop
                        if_c add y,x wc         'conditionally add multiplicand into product
                        rcr y,#1 wc             'get next multiplier bit into c.
                                                ' while shift product
                        djnz t,#:loop           'loop until done
mult_ret                ret   


'------------------------------------
'Uninitialized Data
'------------------------------------
' NOTE: Usually uninitialized data would appear at the end of a code module, but since the OS module will be dynmacially
'       generating code beginning at the "CONDUIT_engine_splice" label the data is located here where it will not be
'       overwritten.
p_frame_counter                 nop               
previous_microframe             nop
current_microframe              nop

x                               nop
y                               nop 
t                               nop
p_ss_gain_in_socket             nop               
p_ss_gain_out_socket            nop
p_ss_gain_control_socket        nop
sign_bit                        nop

                        '------------------------------------
                        ' The conduit engine workhorse code is dynamically created by the main OS thread
                        ' at the splice address below
                        '------------------------------------
CONDUIT_engine_splice   jmp     #frame_sync

                        fit             