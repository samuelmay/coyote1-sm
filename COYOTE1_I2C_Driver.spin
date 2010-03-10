''=======================================================================  
'' TITLE: COYOTE1_I2C.SPIN
''
'' DESCRIPTION:
''    I2C Driver.
''    This is a wrapper around Michael Green's "Basic I2C Driver". This
''    driver returns unified error codes and always performs waits on
''    writes.  
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
''  002  08-31-08  Change WriteWait timeout to hardcode operational frequency insead of using clkfreq.
''  003  11-01-08  Add temporary workaround for the clkfreq/tube distorion bug posted at http://www.openstomp.com/phpbb/viewtopic.php?f=4&t=19
''
''=======================================================================

OBJ

   hw             : "COYOTE1_HW_Definitions.spin"  'Hardware definitions 
   i2c            : "Basic_I2C_Driver.spin"       'Michael Green's i2c driver

PUB  WriteWord (device_address, address_register, data) | err_code
  err_code := hw#ERR__SUCCESS
  if i2c.WriteWord(i2c#BootPin, device_address, address_register, data)
    err_code := hw#ERR__I2C_WRITE_FAIL
  else
    err_code := WriteWait(device_address, address_register)

  return(err_code)

PUB ReadWord  (device_address, address_register, data_p) | err_code, data   
  err_code := hw#ERR__SUCCESS
  data := i2c.ReadWord(i2c#BootPin, device_address, address_register)
  if(data == -1)
    err_code := hw#ERR__I2C_READ_FAIL
  else
    word[data_p] := data
    
  return(err_code)

PUB ReadLong  (device_address, address_register, data_p) | err_code, data
  long[data_p] := i2c.ReadLong(i2c#BootPin, device_address, address_register)
  return(hw#ERR__SUCCESS)
  
PUB  WriteBlock (device_address, address_register, data_size, source_address) | err_code, write_size
  'NOTE:  This procedure assumes that the beginning of the data is page aligned.
  '       The EEPROM device supports 256 byte pages
  err_code := hw#ERR__SUCCESS

  repeat while ((data_size <> 0) and  (err_code == hw#ERR__SUCCESS))  

    'Determine size to write
    if (data_size =< hw#EEPROM_PAGE_WRITE_SIZE)
      write_size := data_size
    write_size := hw#EEPROM_PAGE_WRITE_SIZE

    'Write the data
    if i2c.WritePage(i2c#BootPin, device_address, address_register, source_address, write_size)
       'Write failed
       err_code := hw#ERR__I2C_WRITE_FAIL
    else
       'Wait for write to complete
       err_code := WriteWait(device_address, address_register)

    'Advance to next chunk of data
    data_size -= write_size
    source_address += write_size
    address_register += write_size

  return(err_code)

PUB  ReadBlock (device_address, address_register, data_size, source_address) | err_code, read_size
  'NOTE:  This procedure assumes that the beginning of the data is page aligned.
  '       The EEPROM device supports 256 byte pages
  err_code := hw#ERR__SUCCESS

  repeat while ((data_size <> 0) and  (err_code == hw#ERR__SUCCESS))  

    'Determine size to write
    'if (data_size =< hw#EEPROM_PAGE_WRITE_SIZE)
      read_size := data_size
    'read_size := hw#EEPROM_PAGE_WRITE_SIZE

    'Write the data
    if i2c.ReadPage(i2c#BootPin, device_address, address_register, source_address, read_size)
       'Read failed
       err_code := hw#ERR__I2C_READ_FAIL

    'Advance to next chunk of data
    data_size -= read_size
    source_address += read_size
    address_register += read_size   

  return(err_code)

PUB WriteWait (device_address, address_register)| err_code, start_time
  err_code := hw#ERR__SUCCESS   
  start_time := cnt                                                 
  repeat while (i2c.WriteWait(i2c#BootPin, device_address, address_register) and (err_code == hw#ERR__SUCCESS))
    'if (cnt - start_time) > (clkfreq / 10)    ' Note: longest expected delay is 10msec. This will wait 100msec before timing out.
    'EPM: The line above is more appropriate.  The line below is a temporary workaround for a bug where the tube distortion patch was causing
    '     the above line to not function correctly (as if clkfreq was returning an incorrect value). 
    if (cnt - start_time) > (80_000_000 / 10) ' Note: longest expected delay is 10msec. This will wait 100msec before timing out.
      err_code := hw#ERR__I2C_WRITE_TIMEOUT
   
  return(err_code)

'
' The following 4 functions are just pass throughs to the Basic_i2c_driver code.  They are
' implemented temporarily for expansion port testing.
'
PUB Start(SCL)
  i2c.Start(SCL)
PUB Write(SCL, data) : ackbit
  ackbit := i2c.Write(SCL,data)
PUB Read(SCL, ackbit):data
  data := i2c.Read(SCL, ackbit)
PUB Stop(SCL)
  i2c.Stop(SCL)