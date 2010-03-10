''=======================================================================  
'' TITLE: COYOTE1_Serial_Comm.SPIN
''
'' DESCRIPTION:
''    Serial communications engine for the Coyote-1
''
''    All messages between the Coyote-1 and the host PC (i.e. OpenStomp(TM) Workbench) are
''    exchanged using a seral framing protocol consising of a start symbol (STX), an end
''    symbol (ETX), and an escape symbol (DLE).  Messages are initiated with an STX and
''    terminated by an ETX.  If a framing symbol (STX, ETX, or DLE) appears in the
''    message payload a preceeding DLE will be insterted to indicate the following symbol is
''    a data character rather than a framing symbol.
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
''  002  10-19-08  Expand module description.
''
''=======================================================================

CON


  MSG_FLAG__START        = $02  'STX
  MSG_FLAG__END          = $03  'ETX
  MSG_FLAG__ESCAPE       = $10  'DLE

  '------------------------------------
  'Message types
  '------------------------------------

  'Commands
  MSG_CMD__PING                 = $20
  MSG_CMD__ARM_CAPTURE          = $21
  MSG_CMD__GET_MODULE_INFO      = $22
  MSG_CMD__CLEAR_SHUTTLE_BUF    = $23
  MSG_CMD__WRITE_SHUTTLE_BUF    = $24
  MSG_CMD__CHECKSUM_SHUTTLE_BUF = $25
  MSG_CMD__READ_SHUTTLE_BUF     = $26
  MSG_CMD__EXECUTE_RPC          = $27
  MSG_CMD__GET_PATCH_INFO       = $28 
  
  'Responses
  MSG_RSP__PING                 = $40
  MSG_RSP__ARM_CAPTURE          = $41
  MSG_RSP__GET_MODULE_INFO      = $42
  MSG_RSP__CLEAR_SHUTTLE_BUF    = $43
  MSG_RSP__WRITE_SHUTTLE_BUF    = $44
  MSG_RSP__CHECKSUM_SHUTTLE_BUF = $45
  MSG_RSP__READ_SHUTTLE_BUF     = $46
  MSG_RSP__EXECUTE_RPC          = $47
  MSG_RSP__GET_PATCH_INFO       = $48      
                                 
  'Indications                   
  MSG_IND__CAPTURE_DATA         = $62
  MSG_IND__DIAGNOSTIC_STRING    = $63

 
  RX_FLAGS__MESSAGE_IN_PROGRESS = %00000001
  RX_FLAGS__ESCAPE_SEQUENCE     = %00000010

  RX_BUFFER_SIZE = 64
  TX_BUFFER_SIZE = 64  
  
VAR

  long  rx__msg_index
  byte  rx__flags
  byte  rx__message[RX_BUFFER_SIZE]
  byte  tx__message[TX_BUFFER_SIZE]
  long  ss__block_p
  long  shuttle_buffer_write_index
  byte  tx_checksum
  
  byte  get_module_info__in_progress
  byte  current_dynamic_module

OBJ
  hw          : "COYOTE1_HW_Definitions.spin"  'Hardware definitions
  uart        : "COYOTE1_FullDuplex.spin"     'Parallax serial driver + COYOTE-1 driver
  
PUB Start(ss__block_p_arg)

  ss__block_p := ss__block_p_arg
  'long[ss__block_p + hw#SS_OFFSET__DEBUG_PASS] := $44
  
  rx__msg_index := 0
  rx__flags := 0
  get_module_info__in_progress := false

  uart.Start(31,30,ss__block_p, hw#SERIAL_BAUD_RATE)

PUB Process_RX | i, j, rx_byte, rpc_command_p, length, shuttle_buffer_p, completed_command

  '-----------------------------------
  'Send response if there was a pending (and now completed) RPC
  '-----------------------------------
  'Determine address of RPC control longword
   rpc_command_p := ss__block_p + hw#SS_OFFSET__RPC_CONTROL
      
  'If a pending RPC was running, and has completed
   if(((long[rpc_command_p] & hw#RPC_FLAG__EXECUTE_REQUEST) <> 0) and ((long[rpc_command_p] & hw#RPC_FLAG__EXECUTE_ACK) <> 0)) 

      'Note the RPC command which completed
      completed_command := long[rpc_command_p] & hw#RPC_CMD__MASK
      
      'Clear the request
      long[rpc_command_p] := hw#RPC_CMD__NONE

      'Get pointer to shuttle buffer
      shuttle_buffer_p := long[ss__block_p + hw#SS_OFFSET__SHUTTLE_BUFFER_P]
        
      if (not get_module_info__in_progress)

        if (completed_command == hw#RPC_CMD__GET_PATCH_INFO)
          'This was a "Get Patch Info" RPC which was internally generated to service a "Get Patch Info" command message
          '(not an RPC message) from the host.  Send the data as part of the (already started) response message and terminate it.

          'Copy the patch data
          repeat i from 0 to constant((hw#PATCH_NAME_CHARS * hw#MAX_PATCHES) - 1)
            TX_msg_byte(byte[shuttle_buffer_p+ i])

          'End the message
          TX_msg_end     
          
        else
          'This was a "normal" RPC, initiated by the host computer. Send a response to acknowledge completion.
           
          'Send response
          tx__message[0] := MSG_RSP__EXECUTE_RPC
          TX(@tx__message, 1)

      else
        'The RPC mechanism is being used to fetch module info for a GET_MODULE_INFO request.
        'Send the current module info, then process the next (if one exists)

        'Get module descriptor length
        length := long[shuttle_buffer_p + hw#MDES_OFFSET__SIZE]
        'Send the module descriptor
        repeat i from 0 to (length - 1)
          TX_msg_byte(byte[shuttle_buffer_p+ i])

        'Now continue searching for more modules to send
        get_module_info__in_progress := false
        repeat while ((current_dynamic_module <  hw#MAX_DYNMAIC_MODULES  ) and (not get_module_info__in_progress ))
          'If the module exists in EEPROM
          if ((long[ss__block_p + hw#SS_OFFSET__MODULE_MASK] & ($00000001 << current_dynamic_module)) <> 0)
             'Fetch the module using the RPC mechanism
             'NOTE: this procedure will exit.  When the RPC complets the module will be transmitted (and
             '      the next module RPC requested) in the next ProcessRX() call.
             
             'Determine address of RPC control longword
             j := ss__block_p + hw#SS_OFFSET__RPC_CONTROL
                                   
             'Issue the RPC execution request
             long[j] := hw#RPC_FLAG__EXECUTE_REQUEST | ((current_dynamic_module + hw#MAX_STATIC_MODULES) << hw#RPC_DATA0_SHIFT) | hw#RPC_CMD__MODULE_DESC_FETCH
         
             get_module_info__in_progress := true
         
          else
            'The module does not exist.  Send an empty module descriptor
            TxEmptyModuleDescriptor
            
          ++current_dynamic_module

        if (not get_module_info__in_progress)
          'All module info sent.  End the message.          
          TX_msg_end

  '-----------------------------------
  'Process RX data
  '-----------------------------------
      
  'If a byte has been received
  rx_byte := uart.rxcheck
  repeat while( rx_byte <> -1 )
    if rx__flags & RX_FLAGS__ESCAPE_SEQUENCE
      'The current symbol was preceeded by an escape symbol, so do not interpret
      '  it as a flag regardless of its value.
      if rx__flags & RX_FLAGS__MESSAGE_IN_PROGRESS
        rx__message[rx__msg_index] := rx_byte
        ++rx__msg_index
      rx__flags &= !RX_FLAGS__ESCAPE_SEQUENCE
    else
      'No escape in progress
      if rx__flags & RX_FLAGS__MESSAGE_IN_PROGRESS
        case rx_byte
          MSG_FLAG__START:
            'Unexptected start flag encountered during message. Restart.
            rx__msg_index := 0
            
          MSG_FLAG__ESCAPE:
            'Escape sequence in progress
            rx__flags |= RX_FLAGS__ESCAPE_SEQUENCE   
            
          MSG_FLAG__END:
            'End of message found.  Process the completed message
            Process_Message
            rx__flags &= !RX_FLAGS__MESSAGE_IN_PROGRESS 

          other:
            'Message data; append it
            rx__message[rx__msg_index] := rx_byte
            ++rx__msg_index
      else
        'No message in progress. Look for start flag
        if rx_byte := MSG_FLAG__START
          'Start of message found
          rx__flags |= RX_FLAGS__MESSAGE_IN_PROGRESS
          rx__msg_index := 0

    'check for next byte
    rx_byte := uart.rxcheck 
            

PUB TX_diagnostic_string (string_p) | i
  tx__message[0] := MSG_IND__DIAGNOSTIC_STRING
  i := 0
  repeat while byte[string_p + i] <> 0
    tx__message[1 + i] := byte[string_p + i] 
    ++i   
  TX(@tx__message, i + 1)  

PUB TX (message_p, length) | i, tx_byte

  tx_checksum := 0

  'Send START
  uart.tx(MSG_FLAG__START)

  'Send message
  repeat i from 1 to (length + 1)
    if(i==length + 1)
      'Send checksum
      tx_byte :=  ($100 - (tx_checksum & $ff))
    else
      'Send data
      tx_byte := byte[message_p]
      ++message_p
      tx_checksum += tx_byte
      
    if ((tx_byte == MSG_FLAG__START) or (tx_byte == MSG_FLAG__END) or (tx_byte == MSG_FLAG__ESCAPE))
      'Send an escape before any START, END, or ESCAPE in the message data
      uart.tx(MSG_FLAG__ESCAPE)
    'Send the data
    uart.tx(tx_byte) 
  
  'Send END
  uart.tx(MSG_FLAG__END)   

PUB TX_msg_start
  'Clear checksum
  tx_checksum := 0
  
  'Send START
  uart.tx(MSG_FLAG__START)  

PUB TX_msg_byte(tx_byte)
  tx_checksum += tx_byte
  if ((tx_byte == MSG_FLAG__START) or (tx_byte == MSG_FLAG__END) or (tx_byte == MSG_FLAG__ESCAPE))
    'Send an escape before any START, END, or ESCAPE in the message data
     uart.tx(MSG_FLAG__ESCAPE)
  'Send the data
  uart.tx(tx_byte) 

PUB TX_msg_end
  'Send checksum
  uart.tx($100 - (tx_checksum & $ff))
  
  'Send END
  uart.tx(MSG_FLAG__END) 

PRI Process_Message | i, j, k, sample, s_module_p, size 

  'Verify checksum
  j := 0
  repeat i from 0 to (rx__msg_index - 1)
    j += rx__message[i]
  if(j & $ff <> 0)
    'Checksum failed.  Ignore message
    return

  case rx__message[0]
  
    MSG_CMD__PING:
      ' Send PING response
      tx__message[0] := MSG_RSP__PING
      TX(@tx__message, 1)
      'long[ss__block_p + hw#SS_OFFSET__DEBUG_PASS] := $AA
      long[ss__block_p + hw#SS_OFFSET__DEBUG_PASS] += 1
    

    MSG_CMD__ARM_CAPTURE:
      ' ARM capture
      long[ss__block_p + hw#SS_OFFSET__CAP_STATE] := hw#CAPTURE_STATE__ARM
      
      ' Send ARM response
      tx__message[0] := MSG_RSP__ARM_CAPTURE
      TX(@tx__message, 1)
      'long[ss__block_p + hw#SS_OFFSET__DEBUG_PASS] := $BB

      'Wait for capture to complete
      repeat while long[ss__block_p + hw#SS_OFFSET__CAP_STATE] <> hw#CAPTURE_STATE__DONE

      'Send capture data
      repeat i from 0 to hw#NUM_CAPTURE_SAMPLES - 1
        tx__message[0] := MSG_IND__CAPTURE_DATA
        sample := long[ss__block_p + hw#SS_OFFSET__CAP_SAMPLES + (i<<2)]
        tx__message[1] := i & $00ff
        tx__message[2] := (i & $ff00)>>8 
        tx__message[3] := (sample & $000000ff)
        tx__message[4] := (sample & $0000ff00) >> 8
        tx__message[5] := (sample & $00ff0000) >> 16
        tx__message[6] := ((sample & $ff000000) >> 24) & $ff
        TX(@tx__message, 7)
        
    MSG_CMD__GET_MODULE_INFO:
    
      'Send GET MODULE INFO response
      TX_msg_start
      TX_msg_byte(MSG_RSP__GET_MODULE_INFO)

      'Send the module descriptors for all static Modules
      repeat i from 0 to hw#MAX_STATIC_MODULES - 1  
        s_module_p := long[ss__block_p + hw#SS_OFFSET__STATIC_MOD_DSC_P_0 + (i<<2)]
        if(s_module_p <> 0)
          ' The module exists.  Send it.
          size := long[s_module_p + hw#MDES_OFFSET__SIZE]
          repeat j from 0 to size - 1
             TX_msg_byte(byte[s_module_p + j])
        else
          ' The module does not exist.  Send an empty module descriptor  
          TxEmptyModuleDescriptor  

      'Send the module descriptors for all dynamic Modules
      current_dynamic_module := 0
      get_module_info__in_progress := false
      repeat while ((current_dynamic_module <  hw#MAX_DYNMAIC_MODULES  ) and (not get_module_info__in_progress ))
        'If the module exists in EEPROM
        if ((long[ss__block_p + hw#SS_OFFSET__MODULE_MASK] & ($00000001 << current_dynamic_module)) <> 0)
           'Fetch the module using the RPC mechanism
           'NOTE: this procedure will exit.  When the RPC complets the module will be transmitted (and
           '      the next module RPC requested) in the ProcessRX() handler.
           
           'Determine address of RPC control longword
           j := ss__block_p + hw#SS_OFFSET__RPC_CONTROL
                                 
           'Issue the RPC execution request
           long[j] := hw#RPC_FLAG__EXECUTE_REQUEST | ((current_dynamic_module + hw#MAX_STATIC_MODULES) << hw#RPC_DATA0_SHIFT) | hw#RPC_CMD__MODULE_DESC_FETCH

           get_module_info__in_progress := true

        else
          'The module does not exist.  Send an empty module descriptor 
          TxEmptyModuleDescriptor
        ++current_dynamic_module                 

      'If not waiting to fetch dynamic module info
      if (not get_module_info__in_progress)
        'End the message   
        TX_msg_end
        long[ss__block_p + hw#SS_OFFSET__DEBUG_PASS] := 0

    MSG_CMD__GET_PATCH_INFO:

      'Send GET Patch INFO response
      TX_msg_start
      TX_msg_byte(MSG_RSP__GET_PATCH_INFO)

      'Fetch the patch info using the RPC mechanism
      'NOTE: this procedure will exit.  When the RPC complets the patch info will be transmitted
      '      in the ProcessRX() handler.

      'Determine address of RPC control longword
      j := ss__block_p + hw#SS_OFFSET__RPC_CONTROL
                            
      'Issue the RPC execution request
      long[j] := hw#RPC_FLAG__EXECUTE_REQUEST | hw#RPC_CMD__GET_PATCH_INFO

      
    MSG_CMD__CLEAR_SHUTTLE_BUF:

      '---------------------------------
      'Zero the shuttle buffer
      '---------------------------------
      
      'Get base address of the shuttle buffer
      j := long[ss__block_p + hw#SS_OFFSET__SHUTTLE_BUFFER_P]

      'Zero the buffer
      repeat i from 0 to hw#SHUTTLE_BUFFER_SIZE_LW - 1
        long[j + (i<<2)] := 0

      'Send response
      tx__message[0] := MSG_RSP__CLEAR_SHUTTLE_BUF
      TX(@tx__message, 1)

      'Set current index (for writing)
      shuttle_buffer_write_index := 0


    MSG_CMD__WRITE_SHUTTLE_BUF:

      '---------------------------------
      'Write incoming data to the shuttle buffer
      '---------------------------------

      'Get base address of the shuttle buffer
      j := long[ss__block_p + hw#SS_OFFSET__SHUTTLE_BUFFER_P]

      'Copy incoming data to the buffer
      repeat i from 1 to (rx__msg_index - 2)  ' The "-2" is to ignore 1 cmd byte, 1 checksum byte
        byte[j + shuttle_buffer_write_index] := rx__message[i]
        ++shuttle_buffer_write_index

      'Send response
      tx__message[0] := MSG_RSP__WRITE_SHUTTLE_BUF
      TX(@tx__message, 1)

    MSG_CMD__CHECKSUM_SHUTTLE_BUF:

      '---------------------------------
      'Checksum the shuttle buffer
      '---------------------------------

      'Get base address of the shuttle buffer
      j := long[ss__block_p + hw#SS_OFFSET__SHUTTLE_BUFFER_P]

      'Checksum the buffer
      k := 0
      repeat i from 0 to (hw#SHUTTLE_BUFFER_SIZE_LW << 2) - 1 step 4
        k += byte[j + i] + (byte[j + i+1] << 8) + (byte[j + i+2] << 16)  + (byte[j + i+3] << 24)  

      'Send response
      tx__message[0] := MSG_RSP__CHECKSUM_SHUTTLE_BUF
      tx__message[1] := (k & $000000ff)
      tx__message[2] := (k & $0000ff00) >> 8
      tx__message[3] := (k & $00ff0000) >> 16
      tx__message[4] := (k & $ff000000) >> 24
      TX(@tx__message, 5)

    MSG_CMD__READ_SHUTTLE_BUF:

      '---------------------------------
      'Return the shuttle buffer
      '---------------------------------
      
      TX_msg_start
      TX_msg_byte(MSG_RSP__READ_SHUTTLE_BUF)

      'Get base address of the shuttle buffer
      j := long[ss__block_p + hw#SS_OFFSET__SHUTTLE_BUFFER_P]
      
      repeat i from 0 to (hw#SHUTTLE_BUFFER_SIZE_LW << 2) - 1
        TX_msg_byte(byte[j + i])                     

      'End the message   
      TX_msg_end

    MSG_CMD__EXECUTE_RPC:
    
      '---------------------------------
      'Execute an RPC (remote procedure call)
      '---------------------------------
      ' This issues a command to the main OS module, and returns status when the
      ' main OS module indicates that the command has completed.
      '---------------------------------
      
      'Determine address of RPC control longword
      j := ss__block_p + hw#SS_OFFSET__RPC_CONTROL

      'Issue the RPC execution request
      long[j] := hw#RPC_FLAG__EXECUTE_REQUEST | ( rx__message[2] << hw#RPC_DATA0_SHIFT) | rx__message[1] 

      'NOTE: the response will get sent in the main Process_RX call when the
      '      RPC has completed.  We cannot block and poll for it becasue the RPC is going
      '      to get executed on this thread (cog) after this serial call exists.
      
PUB TxEmptyModuleDescriptor  | j
  'Transmit module descriptor header
  TX_msg_byte(constant((hw#MDES_FORMAT_1 >> 0) & $ff))
  TX_msg_byte(constant((hw#MDES_FORMAT_1 >> 8) & $ff))
  TX_msg_byte(constant((hw#MDES_FORMAT_1 >> 16) & $ff))
  TX_msg_byte(constant((hw#MDES_FORMAT_1 >> 24) & $ff)) 

  'Transmit a zero module descriptor length (signifies an empty (nonexistant) module descriptor)
  repeat j from 1 to 4
    TX_msg_byte(0)        
        
  