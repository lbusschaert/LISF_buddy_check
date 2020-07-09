! modified by David and Shugong on 07/25/2018 for supporting convective precipitation. 
! modified by Shugong on 10/03/2018. Current version only supports total rainfall and total snowfall (io_precip_type=2 for JULES) 
subroutine tile_to_forcing(n, t)
  use jules50_lsmMod
  use forcing
  use LIS_coreMod, only : LIS_rc
  use LIS_FORC_AttributesMod  
  use LIS_constantsMod, only : LIS_CONST_TKFRZ  
  use debug_latlon 
  use LIS_coreMod, only : LIS_rc
  implicit none 
  integer, intent(in) :: n, t

! Specific humidity (Kg/Kg)
  qw_1_ij(1,1) = jules50_struc(n)%jules50(t)%qair/jules50_struc(n)%forc_count
! Air temperature (k)
  tl_1_ij(1,1) = jules50_struc(n)%jules50(t)%tair/jules50_struc(n)%forc_count
! W'ly wind component (m s-1)
  u_1_ij(1,1)  = jules50_struc(n)%jules50(t)%wind_e/jules50_struc(n)%forc_count
! S'ly wind component (m s-1)
  v_1_ij(1,1)  = jules50_struc(n)%jules50(t)%wind_n/jules50_struc(n)%forc_count
! Surface pressure (Pascals)
  pstar_ij(1,1)   = jules50_struc(n)%jules50(t)%psurf/jules50_struc(n)%forc_count
! W'ly component of surface current (m s-1)
  u_0_ij(1,1)  = 0.0
! S'ly component of surface current (m s-1)
  v_0_ij(1,1)  = 0.0

! Using the Loobos configuration, only use total rainfall and total snow fall
! All rain goes to Large-scale rainfall (kg m-2/s)
  if(jules50_struc(n)%jules50(t)%rainf .ne. LIS_rc%udef) then
    ls_rain_ij(1,1) = jules50_struc(n)%jules50(t)%rainf/ jules50_struc(n)%forc_count
  else
    ls_rain_ij(1,1) = 0.0
  endif

  if (LIS_FORC_Snowf%selectOpt .eq. 1) then
    ls_snow_ij(1,1) = jules50_struc(n)%jules50(t)%snowf / jules50_struc(n)%forc_count
  else 
    if (jules50_struc(n)%jules50(t)%tair .lt. LIS_CONST_TKFRZ) then
      ls_snow_ij(1,1)  = ls_rain_ij(1,1)
      ls_rain_ij(1,1)  = 0.0
    else
      ls_snow_ij(1,1)  = 0.0
    endif
  endif
! convective rain and convective snow set to 0   
  con_rain_ij(1,1) = 0.0
  con_snow_ij(1,1) = 0.0
!-------------------------- END of SNOW ---------------------------!

! Surface downward SW radiation (W m-2)
  sw_down_ij(1,1) = jules50_struc(n)%jules50(t)%swdown/jules50_struc(n)%forc_count
! Surface downward LW radiation (W m-2)
  lw_down_ij(1,1) = jules50_struc(n)%jules50(t)%lwdown/jules50_struc(n)%forc_count
  !diurnal_temperature_range(1,1)                      ! diurnal temperature range (K), used when l_dailydisagg=T
  !diff_rad(1,1)       ! Input diffuse radiation (W m-2)
end subroutine tile_to_forcing
