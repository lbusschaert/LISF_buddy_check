!-----------------------BEGIN NOTICE -- DO NOT EDIT-----------------------
! NASA Goddard Space Flight Center
! Land Information System Framework (LISF)
! Version 7.3
!
! Copyright (c) 2020 United States Government as represented by the
! Administrator of the National Aeronautics and Space Administration.
! All Rights Reserved.
!-------------------------END NOTICE -- DO NOT EDIT-----------------------
!BOP
! !ROUTINE: noahmp36_getSig0VHpred
! \label{noahmp36_getSig0VHpred}
!
! !REVISION HISTORY:
! 13 May 2021: Sara Modanesi, Michel Bechtold; Initiated specifications for VH polarization
! 18 June 2021: Michel Bechtold; bug fix obs_ngrid needed for multiple obs 
! !INTERFACE:

subroutine noahmp36_getSig0VHpred(n,k,obs_pred)

! !USES:

  use ESMF
  use LIS_coreMod, only : LIS_rc,LIS_surface
  use LIS_RTMMod,  only : LIS_forwardState, LIS_RTM_run
  use LIS_logMod,  only : LIS_verify

  use noahmp36_lsmMod

!EOP

  implicit none
! !ARGUMENTS: 
  integer, intent(in)    :: n
  integer, intent(in)    :: k
  real                   :: obs_pred(LIS_rc%obs_ngrid(k),LIS_rc%nensem(n))
  integer                :: count1(LIS_rc%obs_ngrid(k),LIS_rc%nensem(n))
!
! !DESCRIPTION:
!
!  Returns the Backscatter VH obs pred (model's estimate of 
!  observations) for data assimilation
! 
!  The arguments are: 
!  \begin{description}
!  \item[n] index of the nest \newline
!  \item[obs\_pred] model's estimate of observations \newline
!  \end{description}
!EOP

  integer                :: i,t,m,gid
  real, pointer          :: s0VH(:)
  type(ESMF_Field)       :: varField
  integer                :: status

!!call the forward model
call LIS_RTM_run(n)

  call ESMF_StateGet(LIS_forwardState(n), "WCM_Sig0VH", varField, rc=status)
!LIS_histDAtaMod
  call LIS_verify(status, &
       "Error in StateGet in noahmp36_getSig0VHPred for WCM_Sig0VH")

  call ESMF_FieldGet(varField, localDE=0,farrayPtr=s0VH, rc=status)!variable
!s0VH previously defined
  call LIS_verify(status, &
       'Error in FieldGet in noahmp36_getSig0VHPred for WCM_Sig0VH')

  obs_pred = 0.0
  count1 = 0.0
  do i=1,LIS_rc%npatch(n,LIS_rc%lsm_index),LIS_rc%nensem(n)
     do m=1,LIS_rc%nensem(n)
        t = i+m-1
        gid = LIS_surface(n,LIS_rc%lsm_index)%tile(t)%index
        obs_pred(gid,m)= obs_pred(gid,m) + s0VH(t)
        count1(gid,m) = count1(gid,m) +1
     enddo
  enddo

  do i=1,LIS_rc%obs_ngrid(k)
     do m=1,LIS_rc%nensem(n)
        obs_pred(i,m) = obs_pred(i,m)/(count1(i,m))
     enddo
  enddo

end subroutine noahmp36_getSig0VHpred

