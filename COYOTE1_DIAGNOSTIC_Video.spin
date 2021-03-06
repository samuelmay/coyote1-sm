''=======================================================================  
'' TITLE: COYOTE1_DIAGNOSTIC_Video.SPIN
''
'' DESCRIPTION:
''   This is an adaptation of Bamse's "50 line graphics driver", modified to
''   display a set of vertical color bars for video testing, and an audio
''   oscilloscope for audio loopback testing.  Bamse's driver is about
''   as short as it is possible to make a propeller video driver, and is 
''   excellently documented.  You can find it on the Hydra forums
''   here: http://forums.parallax.com/forums/default.aspx?f=33&m=277812
''   Thank you Bamse!
''
'' COPYRIGHT:
''   (C)2008 Bamse  
''   
'' LICENSING:                                                      
''   The 50 line graphics driver is free software: you can redistribute it and/or modify
''   it under the terms of the GNU General Public License as published by
''   the Free Software Foundation, either version 3 of the License, or
''   (at your option) any later version.
''   
''   The 50 line graphics driver is distributed in the hope that it will be useful,
''   but WITHOUT ANY WARRANTY; without even the implied warranty of
''   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
''   GNU General Public License for more details.
''   
''   You should have received a copy of the GNU General Public License
''   along with the 50 line graphics driver. If not, see <http://www.gnu.org/licenses/>.
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
  MODE__COLOR_BAR          = 1
  MODE__OSCILLOSCOPE       = 2
    
VAR

byte video_cog

PUB start(video_diag_control_block_p)

  ' Start a new cog with our video driver.
  video_cog := cognew(@entry, video_diag_control_block_p)

PUB stop
  cogstop(video_cog)

DAT                     org     0
entry                   jmp     #Start_of_driver         'Start here...

' NTSC sync stuff.
NTSC_color_freq                 long  3_579_545                                 ' NTSC Color Frequency
NTSC_hsync_VSCL                 long  39 << 12 + 624                            ' Used for the Horisontal Sync 
NTSC_active_VSCL                long  188 << 12 + 3008                          ' Used for the Vertical sync
NTSC_hsync_pixels               long  %%11_0000_1_2222222_11                    ' Horizontal sync pixels
NTSC_vsync_high_1               long  %%1111111_2222222_11                      ' Vertical sync signal part one for lines 1-6 and 13 to 18
NTSC_vsync_high_2               long  %%1111111111111111                        ' Vertical sync signal part two for lines 1-6 and 13 to 18
NTSC_vsync_low_1                long  %%2222222222222222                        ' Vertical sync signal part one for lines 7-12
NTSC_vsync_low_2                long  %%22_1111111_2222222                      ' Vertical sync signal part two for lines 7-12
NTSC_sync_signal_palette        long  $00_00_02_8A                              ' The sync Palette

' The bitmask for the Hydra Video output pins
tvport_mask                     long  %0000_0111<<24                            ' Bitmask for Pin 24 to 26

NTSC_Num_Graphic_Lines          long  244                                       ' Number of usable lines.
NTSC_Graphics_Pixels_VSCL       long  16 << 12 + 64                             ' 16 clocks per pixel, 64 clocks per frame.
NTSC_User_Palette1              long  $DE_0D_AE_D8                              ' CYAN, BLUE, GREEN, RED   
NTSC_User_Palette2              long  $07_02_8E_3E                              ' WHITE, BLACK, YELLOW, MAGENTA
NTSC_Palette_Oscilloscope       long  $D8_D8_07_02                              ' RED, RED, WHITE, BLACK

NTSC_Pixel_increment            long  %%1111                                  
NTSC_Tiles_Per_Line             long  47                                        ' Tiles per line.

' Loop counters.
line_loop                       long  $0                                        ' Line counter...
tile_loop                       long  $0                                        ' Tile counter...

' General Purpose Registers
r0                              long  $0                                        ' Initialize to 0
r1                              long  $0
r2                              long  $0
r3                              long  $0


'========================== Start of the actual driver =============================================

Start_of_driver
                        rdlong  mode, PAR                 'Retreive operational mode from the diag video control block
                        
                        mov     r0, PAR                   'Retrieve left audio capture pointer from the diag video control block  
                        add     r0, #4
                        rdlong  p_cap_l_buffer, r0
                        
                        add     r0, #4                    'Retrieve right audio capture pointer from the diag video control block  
                        rdlong  p_cap_r_buffer, r0
                       
                        ' VCFG, setup Video Configuration register and 3-bit tv DAC pins to output
                        movs    VCFG, #%0000_0111                               ' VCFG'S = pinmask (pin31: 0000_0111 : pin24)
                        movd    VCFG, #3                                        ' VCFG'D = pingroup (grp. 3 i.e. pins 24-31)
                        movi    VCFG, #%0_10_101_000                            ' Baseband video on bottom nibble, 2-bit color, enable chroma on baseband
                        or      DIRA, tvport_mask                               ' Set DAC pins to output

                        ' CTRA, setup Frequency to Drive Video
                        movi    CTRA,#%00001_111                                ' pll internal routed to Video, PHSx+=FRQx (mode 1) + pll(16x)
                        mov     r1, NTSC_color_freq                             ' r1: Color frequency in Hz (3.579_545MHz)
                        rdlong  r2, #0                                          ' Copy system clock from main memory location 0. (80Mhz)
                        ' perform r3 = 2^32 * r1 / r2
                        mov     r0,#32+1
:loop                   cmpsub  r1,r2           wc
                        rcl     r3,#1
                        shl     r1,#1
                        djnz    r0,#:loop
                        mov     FRQA, r3                                        ' Set frequency for counter A


'========================== Start of Frame Loop ==============================================
                        
frame_loop

'========================== Scan Lines =======================================================
                        
                        mov     line_loop, NTSC_Num_Graphic_Lines               ' Load the line loop with user lines, 244.
                        mov     p_cap_l_current, p_cap_l_buffer
                        mov     p_cap_r_current, p_cap_r_buffer
                        
user_upper_lines        mov     VSCL, NTSC_hsync_VSCL                           ' Setup VSCL for horizontal sync.
                        waitvid NTSC_sync_signal_palette, NTSC_hsync_pixels     ' Generate sync.

                        mov     tile_loop, NTSC_Tiles_Per_Line                  ' Set up the tile loop with 47 tiles.
                        mov     VSCL, NTSC_Graphics_Pixels_VSCL                 ' Setup VSCL for user pixels.

                        cmp     mode, #MODE__OSCILLOSCOPE  wz
                  if_z  jmp     #_oscope

                        '-----------------------------------------------------
                        ' Render COLOR BAR test pattern
                        '-----------------------------------------------------       
                        'In the following section:
                        '  r0 contains the NTSC pixels        (cycles for each bar: %%0000, %%1111, %%2222, %%3333)
                        '  r1 counts down to the palette swap (4 bars per palette)
                        '  r2 counts down the tiles per bar   (6 tiles per vertical bar)
                        '  r3 contains the NTSC palette       (two palettes are used, one for each group of 4 bars)
                        mov     r0, #0
                        mov     r1, #4
                        mov     r3, NTSC_User_Palette1  
                        mov     r2, #6
                        
_colorbar_tile_loop     waitvid r3, r0                                          ' Draw the tile.
                        djnz    r2, #_colorbar_skip
                        add     r0, NTSC_Pixel_increment
                        mov     r2, #6
                        djnz    r1, #_colorbar_skip
                        mov     r3, NTSC_User_Palette2
                        mov     r0, #0                 
_colorbar_skip          djnz    tile_loop, #_colorbar_tile_loop                 ' loop throug the 47 tiles.

                        djnz    line_loop, #user_upper_lines                    ' Loop through the 122 user video lines.
                        jmp     #_horizontal_sync

                        '-----------------------------------------------------
                        ' Render OSCILLOSCOPE
                        '-----------------------------------------------------
_oscope                 rdlong  left_tile, p_cap_l_current
                        add     p_cap_l_current, #4
                        sar     left_tile, #25
                        add     left_tile, #94
                        mov     left_pixel, left_tile
                        and     left_pixel, #$3
                        shl     left_pixel, #1
                        shr     left_tile, #2

                        rdlong  right_tile, p_cap_r_current
                        add     p_cap_r_current, #4
                        sar     right_tile, #25
                        add     right_tile, #94
                        mov     right_pixel, right_tile
                        and     right_pixel, #$3
                        shl     right_pixel, #1
                        shr     right_tile, #2

_oscope_tile_loop       cmp     tile_loop, left_tile   wz
                  if_z  mov     r1, #%%1000
                  if_z  shr     r1, left_pixel
                  if_nz mov     r1, #%%0000
                        cmp     tile_loop, right_tile  wz
                  if_z  mov     r2, #%%3000
                  if_z  shr     r2, right_pixel
                  if_z  or      r1, r2
                        waitvid NTSC_Palette_Oscilloscope, r1                   ' Draw the tile.              
                        djnz    tile_loop, #_oscope_tile_loop                   ' loop throug the 47 tiles.

                        djnz    line_loop, #user_upper_lines                    ' Loop through the 122 user video lines.
                        jmp     #_horizontal_sync                         

'========================== The 16 lines of Horizontal sync ==================================
_horizontal_sync                        
                        mov     line_loop, #6                                   ' Line 244, start of first high sync.
vsync_high1             mov     VSCL, NTSC_hsync_VSCL
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_high_1
                        mov     VSCL, NTSC_active_VSCL
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_high_2
                        djnz    line_loop, #vsync_high1

                        mov     line_loop, #6                                   ' Line 250, start of the Seration pulses.
vsync_low               mov     VSCL, NTSC_active_VSCL
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_low_1
                        mov     VSCL,NTSC_hsync_VSCL 
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_low_2
                        djnz    line_loop, #vsync_low

                        mov     line_loop, #6                                   ' Line 256, start of second high sync.
vsync_high2             mov     VSCL, NTSC_hsync_VSCL
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_high_1
                        mov     VSCL, NTSC_active_VSCL
                        waitvid NTSC_sync_signal_palette, NTSC_vsync_high_2
                        djnz    line_loop, #vsync_high2

'========================== End of Frame Loop =============================================

                        jmp     #frame_loop                                     ' And repeat for ever...

'Registers

mode                    res     1
p_cap_l_buffer          res     1
p_cap_r_buffer          res     1
p_cap_l_current         res     1
p_cap_r_current         res     1

right_tile              res     1
right_pixel             res     1

left_tile               res     1
left_pixel              res     1                                       