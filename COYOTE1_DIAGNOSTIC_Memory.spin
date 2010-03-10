''=======================================================================  
'' TITLE: COYOTE1_DIAGNOSTIC_Memory.spin        
''
'' DESCRIPTION:
''   Implements a full set/clear test of every SRAM location.  This
''   module is implemented in assembly because a full set/clear test
''   performed in spin is prohibitively time consuming.
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
''  1.0.0  10-16-08  Initial Release.
''
''======================================================================= 

CON

  ' Audio sample capture states
  STATE_RUNNING  = 0
  STATE_FAILED   = 1
  STATE_PASSED   = 2
  
VAR

  byte memdiag_cog
  
OBJ
  hw        :       "COYOTE1_HW_Definitions.spin"  'Hardware definitions        


PUB start (mem_diag_control_block_p)

  memdiag_cog := cognew(@_module_entry, mem_diag_control_block_p)

PUB stop

  cogstop(memdiag_cog)
  
DAT
                        
'------------------------------------
'Module Code
'------------------------------------
                        org
                        
_module_entry
                        mov     p_state, PAR                                      'Get pointer to Memtest state
                        mov     p_fail_addr, PAR                                  'Get pointer to Memtest failure address  
                        add     p_fail_addr, #4                                   
                        mov     p_fail_data_wrote, PAR                            'Get pointer to Memtest write value 
                        add     p_fail_data_wrote, #8                             
                        mov     p_fail_data_read, PAR                             'Get pointer to Memtest read value
                        add     p_fail_data_read, #12

                        '------------------------------------
                        'Init
                        '------------------------------------   

                        'Set MEMBUS interface as outputs
                        or       dira, PINGROUP__MEM_INTERFACE
                        or       dira, PIN__LCD_MUX
                        andn     outa, PIN__LCD_MUX
                        
                        '------------------------------------
                        'Test SRAM
                        '------------------------------------
                        mov     sram_address, #0

                        'Fill SRAM with $a5 and verify
                        mov     sram_data, #$a5     
                        shl     sram_data, #16       ' Shift the data into the MEMBUS bit positions  
                        call    #_do_sram_test

                        'Fill SRAM with $5a and verify
                        mov     sram_data, #$5a     
                        shl     sram_data, #16       ' Shift the data into the MEMBUS bit positions  
                        call    #_do_sram_test

                        '------------------------------------
                        'Indicate PASS
                        '------------------------------------
                        mov     r1, #STATE_PASSED
                        wrlong  r1, p_state
_stop1                  jmp     #_stop1   'Halt here forever                  
                        
'------------------------------------
'SRAM Write/Read test
'------------------------------------
_do_sram_test           nop

                        'Lock MEMBUS semaphore
_lock1                  lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock1

                        'Load SRAM address
                        call    #_set_SRAM_address

                        'Setup write size
                        mov     r1, SRAM_SIZE

                        'Setup Write
                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__WRITE_BYTE
                        andn    outa, PINGROUP__MEMBUS   
                        or      outa, sram_data

                        'Write data
_write_loop_1           or      outa, PIN__MEMBUS_CLK
                        andn    outa, PIN__MEMBUS_CLK
                        djnz    r1, #_write_loop_1

                        andn    outa, PINGROUP__MEM_INTERFACE
                        andn    dira, PINGROUP__MEMBUS 

                        '------------------------------------
                        'Read SRAM
                        '------------------------------------
                        'Load SRAM address
                        call    #_set_SRAM_address

                        'Setup read size
                        mov     r1, SRAM_SIZE

                        'Setup Read
                        andn    dira, PINGROUP__MEMBUS
                        andn    outa, PINGROUP__MEMBUS_CNTL
                        or      outa, #hw#MEMBUS_CNTL__READ_BYTE

                        'Read and verify data
 _read_loop_1           or      outa, PIN__MEMBUS_CLK
                        mov     r2, ina
                        andn    outa, PIN__MEMBUS_CLK
                        and     r2, PINGROUP__MEMBUS
                        cmp     r2, sram_data    wz
               if_nz    jmp     #_compare_error
                        djnz    r1, #_read_loop_1       

                        'Release MEMBUS semaphore 
                        lockclr hw#LOCK_ID__MEMBUS

                        jmp     #_passed

                        '------------------------------------
                        'Indicate FAIL
                        '------------------------------------
_compare_error          'Release MEMBUS semaphore 
                        lockclr hw#LOCK_ID__MEMBUS

                        'Report failure
                        mov     sram_address, SRAM_SIZE
                        sub     sram_address, r1
                        wrlong  sram_address, p_fail_addr
                        shr     sram_data, #16
                        wrlong  sram_data, p_fail_data_wrote
                        shr     r2, #16
                        wrlong  r2, p_fail_data_read
                        mov     r1, #STATE_FAILED
                        wrlong  r1, p_state
_stop2                  jmp     #_stop2   'Halt here forever

_passed
_do_sram_test_ret       ret 

'------------------------------------
'Set SRAM Address
'------------------------------------
_set_SRAM_address

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

_set_SRAM_address_ret   ret

'------------------------------------
'Initialized Data                                      
'------------------------------------
SRAM_SIZE               long   hw#SRAM_SIZE
PINGROUP__MEM_INTERFACE long   hw#PINGROUP__MEM_INTERFACE
PINGROUP__MEMBUS        long   hw#PINGROUP__MEMBUS
PINGROUP__MEMBUS_CNTL   long   hw#PINGROUP__MEMBUS_CNTL 
PIN__MEMBUS_CLK         long   hw#PIN__MEMBUS_CLK
PIN__LCD_MUX            long   hw#PIN__LCD_MUX 

'------------------------------------
'Uninitialized Data
'------------------------------------                          
r1                        res     1
r2                        res     1

p_state                   res     1
p_fail_addr               res     1
p_fail_data_wrote         res     1
p_fail_data_read          res     1

sram_address              res     1
sram_data                 res     1

                          fit                 