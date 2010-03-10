''=======================================================================  
'' TITLE: COYOTE1_FullDuplex.SPIN
''
'' DESCRIPTION:
''    Combines two hardware drivers:
''      Parallax Fill Duplex Serial Driver v1.0
''      (C) 2006 Parallax, Inc.
''
''      Coyote-1 LCD Driver
''      (C) 2008 Eric Moyer
''
'' AUTHORS: Parallax    (portions)
''          Eric Moyer  (portions)                                                      
''
''======================================================================= 
''
''  Revision History
''
''  Rev  Date      Description
''  ---  --------  ---------------------------------------------------
''  001  07-19-08  Initial Release.
''  002  10-19-08  Remove unused code.                                                           
''
''=======================================================================
VAR

  long  cogon, cog

  long  rx_head                 '8 contiguous longs
  long  rx_tail
  long  tx_head
  long  tx_tail
  long  rx_pin
  long  tx_pin
  long  ss_block_p
  long  bit_ticks
  long  buffer_ptr
                     
  byte  rx_buffer[16]           'transmit and receive buffers
  byte  tx_buffer[16]

OBJ

  hw        : "COYOTE1_HW_Definitions.spin"          ' Hardware definitions
 
PUB start(rxpin, txpin, ss__block_p, baudrate) : okay

'' Start serial driver - starts a cog
'' returns false if no cog available

  'stop
  longfill(@rx_head, 0, 4)
  longmove(@rx_pin, @rxpin, 3)
  bit_ticks := clkfreq / baudrate
  buffer_ptr := @rx_buffer
  cognew(@entry,@rx_head)
 

PUB rxcheck : rxbyte

'' Check if byte received (never waits)
'' returns -1 if no byte, $00..$FF if byte

  rxbyte--
  if rx_tail <> rx_head
    rxbyte := rx_buffer[rx_tail]
    rx_tail := (rx_tail + 1) & $F


PUB tx(txbyte)

'' Send byte (may wait for room in buffer)

  repeat until (tx_tail <> (tx_head + 1) & $F)
  tx_buffer[tx_head] := txbyte
  tx_head := (tx_head + 1) & $F
 

DAT

'***********************************
'* Assembly language serial driver *
'***********************************

                        org

entry

                        mov     t1,par                'get rx_pin
                        add     t1,#4 << 2
                        rdlong  t2,t1
                        mov     rxmask,#1
                        shl     rxmask,t2

                        add     t1,#4                 'get tx_pin
                        rdlong  t2,t1
                        mov     txmask,#1
                        shl     txmask,t2

                        add     t1,#4                 'get system status block base pointer
                        rdlong  ss__display_buffer_p, t1
                        mov     ss__flags_p, ss__display_buffer_p
                        mov     ss__debug_pass_p, ss__display_buffer_p
                        add     ss__display_buffer_p, #(hw#SS_OFFSET__DISPLAY_BUFFER)
                        add     ss__flags_p,          #(hw#SS_OFFSET__FLAGS)
                        add     ss__debug_pass_p,     #(hw#SS_OFFSET__DEBUG_PASS)

                        add     t1,#4                 'get bit_ticks
                        rdlong  bitticks,t1

                        add     t1,#4                 'get buffer_ptr
                        rdlong  rxbuff,t1
                        mov     txbuff,rxbuff
                        add     txbuff,#16

                        or      outa,txmask           'init tx pin to high output
                        or      dira,txmask

                        mov     txcode,#transmit      'set initial receive code ptr
                        mov     lcdcode,#_output_lcd   'set initial lcd code ptr
                        
                        'Initialize LCD driver
                        mov     lcd_current_char_index, #(hw#LCD_CHARS - 1) 'start on last character
                        or      dira, LCD_DIRA_INIT   ' initialize LCD pin directions


'====================================================================================================
' Serial Receive 
'==================================================================================================== 
receive                 jmpret  rxcode,txcode         'run transmit code, then return

                        test    rxmask,ina      wc    'wait for start bit
        if_c            jmp     #receive

                        mov     rxbits,#9             'ready to receive byte
                        mov     rxcnt,bitticks
                        shr     rxcnt,#1
                        add     rxcnt,cnt                          

:bit                    add     rxcnt,bitticks        'ready next bit period

:wait                   jmpret  rxcode,txcode         'run transmit code

                        mov     t1,rxcnt              'check if bit receive period done
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        test    rxmask,ina      wc    'get bit
                        rcr     rxdata,#1
                        djnz    rxbits,#:bit

                        shr     rxdata,#32-9          'justify and trim received byte
                        and     rxdata,#$FF

                        rdlong  t2,par                'save received byte and inc head
                        add     t2,rxbuff
                        wrbyte  rxdata,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#$0F
                        wrlong  t2,par

                        jmp     #receive              'byte done, receive next byte

'====================================================================================================
' Serial Transmit 
'==================================================================================================== 
transmit                jmpret  txcode,lcdcode        'run lcd code, then return
                        
                        mov     t1,par                'check for head <> tail
                        add     t1,#2 << 2
                        rdlong  t2,t1
                        add     t1,#1 << 2
                        rdlong  t3,t1
                        cmp     t2,t3           wz
        if_z            jmp     #transmit

                        add     t3,txbuff             'get byte and inc tail
                        rdbyte  txdata,t3
                        sub     t3,txbuff
                        add     t3,#1
                        and     t3,#$0F
                        wrlong  t3,t1

                        or      txdata,#$100          'ready byte to transmit
                        shl     txdata,#1
                        mov     txbits,#10
                        mov     txcnt,cnt

:bit                    test    txdata,#1       wc    'output bit
                        muxc    outa,txmask
                        add     txcnt,bitticks        'ready next cnt

:wait                   jmpret txcode,rxcode          'run receive code

                        mov     t1,txcnt              'check if bit transmit period done
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        shr     txdata,#1             'another bit to transmit?
                        djnz    txbits,#:bit

                        jmp     #transmit             'byte done, transmit next byte


'====================================================================================================
' LCD Driver
'==================================================================================================== 

_output_lcd             jmpret  lcdcode, rxcode        'run receive/transmit code, then return
                        '------------------------------------
                        'If LCD disabled, then just process the LEDs
                        '------------------------------------
                        rdlong  r1, ss__flags_p
                        test    r1, FLAG__LCD_DISABLE  wz
              if_nz     jmp     #_LEDs            

                        '------------------------------------
                        'Fetch the next display character
                        '------------------------------------                      
                        sub     lcd_current_char_index, #1   wc             'advance backwards to next character
              if_c      mov     lcd_current_char_index, #(hw#LCD_CHARS - 1) 'if beginning of display passed, move back to end

                        mov     r1, ss__display_buffer_p                            
                        add     r1, lcd_current_char_index
                        rdbyte  lcd_char, r1
                        shl     lcd_char, #hw#MEMBUS_SHIFT       'Shift character into MEMBUS pin position for writing

                        '------------------------------------
                        'Determine the LCD video memory address
                        '------------------------------------
                        mov     r2, lcd_current_char_index
                        cmp     r2, #hw#LCD_LINE_WIDTH  wc
              if_nc     add     r2, #hw#LCD_LINE2_START_ADDR
                        or      r2, #hw#LCD_CMD__HOME_LINE1
                        shl     r2, #hw#MEMBUS_SHIFT       'Shift address into MEMBUS pin position for writing
                        
                        '------------------------------------
                        'Set the video memory address
                        '------------------------------------

_lock1                  jmpret  lcdcode, rxcode        'run receive/transmit code, then return

                        'Try to get the MEMBUS semaphore
                        lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock1                'if can't get lock, give rx/tx another chance to run

                        'Output the LCD character address
                        or      outa, PIN__LCD_MUX     'enable the LCD mux
                        or      dira, PINGROUP__MEMBUS 'set MEMBUS as output
                        or      outa, r2               'output the LCD address
                        or      outa, PIN__LCD_ENABLE
                        nop
                        andn    outa, PINGROUP__LCD_INTERFACE 'clear all interface pins   
                        andn    dira, PINGROUP__MEMBUS 'set MEMBUS as inputs
                        andn    outa, PIN__LCD_MUX     'clear the LCD MUX
                        
                        'Release the MEMBUS semaphore
                        lockclr hw#LOCK_ID__MEMBUS

                        'Load abort counter
                        mov     abort_count, ABORT_RETRIES     
                        
                        '------------------------------------
                        'Wait for address write to complete (BUSY clear)     
                        '------------------------------------
_lock2                  jmpret  lcdcode, rxcode        'run receive/transmit code, then return
                        
                        'Try to get the MEMBUS semaphore
                        lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock2                'if can't get lock, give rx/tx another chance to run

                        'Check that busy flag is cleared
                        or      outa, PIN__LCD_MUX     'enable the LCD mux
                        or      outa, PIN__LCD_READ
                        or      outa, PIN__LCD_ENABLE
                        andn    dira, PINGROUP__MEMBUS 'set MEMBUS as inputs
                        nop
                        test    PIN__LCD_BUSY_FLAG, ina   wc  'check the BUSY flag
                        andn    outa, PINGROUP__LCD_INTERFACE 'clear all interface pins

                        'Release the MEMBUS semaphore
                        lockclr hw#LOCK_ID__MEMBUS

                        'Update abort counter
                        sub     abort_count, #1   wz 
                        
       if_c_and_nz      jmp     #_lock2                'if BUSY is set then keep polling
   
                        '------------------------------------
                        'Write the character
                        '------------------------------------
_lock3                  jmpret  lcdcode, rxcode        'run receive/transmit code, then return

                        'Try to get the MEMBUS semaphore
                        lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock3                'if can't get lock, give rx/tx another chance to run

                        'Output the LCD character address
                        or      outa, PIN__LCD_MUX     'enable the LCD mux
                        or      dira, PINGROUP__MEMBUS 'set MEMBUS as output
                        or      outa, lcd_char         'output the LCD character data
                        or      outa, PIN__LCD_REGSEL   
                        or      outa, PIN__LCD_ENABLE
                        nop
                        andn    outa, PINGROUP__LCD_INTERFACE 'clear all interface pins 
                        andn    dira, PINGROUP__MEMBUS 'set MEMBUS as inputs
                        andn    outa, PIN__LCD_MUX     'clear the LCD MUX

                        'Release the MEMBUS semaphore
                        lockclr hw#LOCK_ID__MEMBUS

                        'Load abort counter
                        mov     abort_count, ABORT_RETRIES
                            
                        '------------------------------------
                        'Wait for character write to complete (BUSY clear)
                        '------------------------------------
_lock4                  jmpret  lcdcode, rxcode        'run receive/transmit code, then return
                        
                        'Try to get the MEMBUS semaphore
                        lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_lock4                'if can't get lock, give rx/tx another chance to run

                        'Check that busy flag is cleared
                        or      outa, PIN__LCD_MUX     'enable the LCD mux
                        or      outa, PIN__LCD_READ
                        or      outa, PIN__LCD_ENABLE
                        andn    dira, PINGROUP__MEMBUS 'set MEMBUS as inputs
                        nop
                        test    PIN__LCD_BUSY_FLAG, ina   wc  'check the BUSY flag
                        andn    outa, PINGROUP__LCD_INTERFACE 'clear all interface pins

                        'Release the MEMBUS semaphore
                        lockclr hw#LOCK_ID__MEMBUS  

                        'Update abort counter
                        sub     abort_count, #1   wz
                        
        if_c_and_nz     jmp     #_lock4                'if BUSY is set then keep polling
 
                        '------------------------------------
                        'Update LCD Backlight, and LEDs
                        '------------------------------------
_LEDs                   jmpret  lcdcode, rxcode        'run receive/transmit code, then return
                        

                        'Get the flags
                        rdlong  r1, ss__flags_p
                        and     r1, #hw#FLAG__GROUP_LED_LCD
                        xor     r1, #(hw#FLAG__LED_0 | hw#FLAG__LED_1) 'Flip LED bits so they function as active high
                        shl     r1, #hw#MEMBUS_SHIFT    'Shift data into MEMBUS pin position for writing   

                        'Try to get the MEMBUS semaphore
                        lockset hw#LOCK_ID__MEMBUS   wc
              if_c      jmp     #_LEDs                 'if can't get lock, give rx/tx another chance to run
                        
                        or      dira, PINGROUP__MEMBUS 'set MEMBUS as output    
                        or      outa, #hw#MEMBUS_CNTL__SET_GPIO0
                        or      outa, r1
                        nop
                        nop
                        or      outa, #hw#PIN__MEMBUS_CLK
                        nop
                        nop
                        andn    outa, #hw#PIN__MEMBUS_CLK 
                        andn    dira, PINGROUP__MEMBUS 'set MEMBUS as inputs
                        andn    outa, PINGROUP__LCD_INTERFACE 'clear all interface pins     

                        'Release the MEMBUS semaphore
                        lockclr hw#LOCK_ID__MEMBUS
                                                                
                        jmp     #_output_lcd            'process next LCD character

'====================================================================================================
' Initialized Data
'====================================================================================================

PIN__LCD_MUX            long   hw#PIN__LCD_MUX
PIN__LCD_ENABLE         long   hw#PIN__LCD_ENABLE
PIN__LCD_READ           long   hw#PIN__LCD_READ
PIN__LCD_REGSEL         long   hw#PIN__LCD_REGSEL
PIN__LCD_BUSY_FLAG      long   hw#PIN__LCD_BUSY_FLAG
PINGROUP__LCD_INTERFACE long   hw#PINGROUP__LCD_INTERFACE
PINGROUP__MEMBUS        long   hw#PINGROUP__MEMBUS
LCD_CMD__HOME_LINE1     long   hw#LCD_CMD__HOME_LINE1 << 16
LCD_DIRA_INIT           long   hw#PIN__LCD_MUX | hw#PIN__LCD_ENABLE | hw#PIN__LCD_READ | hw#PIN__LCD_REGSEL | hw#PIN__MEMBUS_CLK
ABORT_RETRIES           long   200
FLAG__LCD_DISABLE       long   hw#FLAG__LCD_DISABLE

'====================================================================================================
' Uninitialized Data
'==================================================================================================== 
t1                      res     1
t2                      res     1
t3                      res     1
abort_count             res     1

bitticks                res     1

rxmask                  res     1
rxbuff                  res     1
rxdata                  res     1
rxbits                  res     1
rxcnt                   res     1
rxcode                  res     1

txmask                  res     1
txbuff                  res     1
txdata                  res     1
txbits                  res     1
txcnt                   res     1
txcode                  res     1

'LCD Driver
r1                      res     1
r2                      res     1  
lcdcode                 res     1
lcd_idle_count          res     1
lcd_current_char_index  res     1
lcd_char                res     1

ss__display_buffer_p    res     1   
ss__flags_p             res     1
ss__debug_pass_p        res     1 

                        fit