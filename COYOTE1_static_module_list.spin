''=======================================================================    
'' TITLE: COYOTE1_static_module_list.spin
''
'' DESCRIPTION:
''     This file contains the list of any MODULES which will be staticly
''   linked at compile time.
''     In order to create a dynamic MODULE, the MODULE must first be compiled
''   into the O/S as a static MODULE, then moved to a DYNAMIC module slot
''   using OpenStomp Workbench.
''     Modules are generally developed as STATIC modules so that
''   they can be quickly re-compiled/modified/debugged, then migrated to
''   DYNAMIC modules once they are stable/finished/released.
''     You can use OpenStomp Workbench to load and run DYNAMIC modules you
''   download from the website or the forums without ever needing to
''   link them into your OS build or compile them from source.
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
''  002  10-19-08  Add notes. Comment out unused modules.  Release with no static modules included.
''
''=======================================================================
OBJ

'NOTE:  Only the static MODULES being implemented in the get_static_module_desc_p() call below should be
'       included in this OBJ section.  Including a module which does not get referenced in  
'       get_static_module_desc_p() will still cause the compiler to implement that module in code, which
'       cause an unnecessary  waste of code space.

{  
  
  noisegate:  "COYOTE1_MODULE_NoiseGate"
  chorus:     "COYOTE1_MODULE_Chorus"    
  divebomb:   "COYOTE1_MODULE_Divebomb"

  tremolo:    "COYOTE1_MODULE_Tremolo"
  delay:      "COYOTE1_MODULE_Delay"
  distortion: "COYOTE1_MODULE_Distortion" 
  tunstuff:   "COYOTE1_MODULE_Tunstuff"
  testtone:   "COYOTE1_MODULE_TestTone"
  reverb:     "COYOTE1_MODULE_Reverb"

  lfo:        "COYOTE1_MODULE_LFO"
  utility:    "COYOTE1_MODULE_Utility"
  distortion: "COYOTE1_MODULE_Distortion"   
}


  
  
PUB get_static_module_desc_p(module_index)
  '------------------------------------
  ' NOTE:  In general only 4 or fewer static MODULES can be declared here because each static MODULE
  '        occupies a cog and there are 4 available cogs in a standard Coyote-1 O/S build.  O/S builds
  '        in which additional cogs are occupied with cutom user modifications will have fewer than
  '        4 cogs available for static MODULES.
  '------------------------------------
  case module_index
    
    0:
      return 0 'lfo.get_module_descriptor_p    
    1:
      return 0 'utility.get_module_descriptor_p       
    2:
      return 0 'distortion.get_module_descriptor_p
    3:  
      return 0
    
    other:
      'A zero must be returned for any static module which does not exist
      return 0  
                                            