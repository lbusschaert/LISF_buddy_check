!-----------------------BEGIN NOTICE -- DO NOT EDIT-----------------------
! NASA Goddard Space Flight Center Land Information System (LIS) v7.2
!
! Copyright (c) 2015 United States Government as represented by the
! Administrator of the National Aeronautics and Space Administration.
! All Rights Reserved.
!-------------------------END NOTICE -- DO NOT EDIT-----------------------
!BOP
!
! !MODULE: CGLSlai_Mod
! 
! !DESCRIPTION: 
!   This module contains interfaces and subroutines to
!   handle the CGLS LAI data.
!
!  Available lis.config options:
!
!  CGLS LAI data directory:
!      Path to CGLS files. (Required option)
!  CGLS LAI apply QC flags:
!      Whether to apply QC flags from the files. Only enable this if the files
!      are downloaded from CGLS. (Required option)
!  CGLS LAI is resampled:
!      Whether the files are resampled manually to a regular latitude-longitude
!      grid. If they are, it is assumed that they are all in the data directory
!      without any subdirectories, and follow the naming scheme
!
!          CGLS_LAI_resampled_<res>deg_<YYYY>_<MM>_<DD>.nc
!
!      where <res> is the resolution with two decimals, e.g. 0.25 for quarter
!      degree resolution. (Required option)
!  CGLS LAI spatial resolution:      
!      Spatial resolution of resampled data files, only required if "CGLS LAI
!      is resampled" is set. (Optional)
!  CGLS LAI lat max:
!      Maximum latitude value in case CGLS LAI has been resampled and cropped to
!      a subdomain. (Optional)
!  CGLS LAI lat min:
!      Minimum latitude value in case CGLS LAI has been resampled and cropped to
!      a subdomain. (Optional)
!  CGLS LAI lon max:
!      Maximum longitude value in case CGLS LAI has been resampled and cropped to
!      a subdomain. (Optional)
!  CGLS LAI lon min:
!      Minimum longitude value in case CGLS LAI has been resampled and cropped to
!      a subdomain. (Optional)
!
!  If a rescaling option is set, the following options are also available:
!  - CGLS LAI model CDF file
!  - CGLS LAI observation CDF file
!  - CGLS LAI number of bins in the CDF
!
!  The rescaling option has not been extensively tested and should be used
!  carefully.
! 
! !REVISION HISTORY: 
!  03 Nov 2021    Samuel Scherrer; initial reader based on MCD152AH reader
! 
module CGLSlai_Mod
    ! !USES: 
    use ESMF
    use map_utils
    use, intrinsic :: iso_fortran_env, only: error_unit

    implicit none

    PRIVATE

    !-----------------------------------------------------------------------------
    ! !PUBLIC MEMBER FUNCTIONS:
    !-----------------------------------------------------------------------------
    public :: CGLSlai_setup
    !-----------------------------------------------------------------------------
    ! !PUBLIC TYPES:
    !-----------------------------------------------------------------------------
    public :: CGLSlai_struc
    !EOP
    type, public:: CGLSlai_dec

        character*100          :: version
        logical                :: startMode
        integer                :: nc
        integer                :: nr
        integer                :: mi
        real,     allocatable  :: laiobs1(:)
        real,     allocatable  :: laiobs2(:)
        real                   :: gridDesci(50)    
        real*8                 :: time1, time2
        integer                :: fnd
        integer                :: useSsdevScal
        integer                :: qcflag
        integer                :: isresampled
        real*8                 :: spatialres
        real                   :: scale
        real*8                 ::  dlat, dlon
        real*8                 ::  latmax, latmin, lonmax, lonmin
        real,    allocatable :: rlat(:)
        real,    allocatable :: rlon(:)
        integer, allocatable :: n11(:)
        integer, allocatable :: n12(:)
        integer, allocatable :: n21(:)
        integer, allocatable :: n22(:)
        real,    allocatable :: w11(:)
        real,    allocatable :: w12(:)
        real,    allocatable :: w21(:)
        real,    allocatable :: w22(:)

        real                       :: ssdev_inp
        real,    allocatable       :: model_xrange(:,:,:)
        real,    allocatable       :: obs_xrange(:,:,:)
        real,    allocatable       :: model_cdf(:,:,:)
        real,    allocatable       :: obs_cdf(:,:,:)
        real,    allocatable       :: model_mu(:,:)
        real,    allocatable       :: obs_mu(:,:)
        real,    allocatable       :: model_sigma(:,:)
        real,    allocatable       :: obs_sigma(:,:)

        integer                :: nbins
        integer                :: ntimes

    end type CGLSlai_dec

    type(CGLSlai_dec),allocatable :: CGLSlai_struc(:)

contains

    !BOP
    ! 
    ! !ROUTINE: CGLSlai_setup
    ! \label{CGLSlai_setup}
    ! 
    ! !INTERFACE: 
    subroutine CGLSlai_setup(k, OBS_State, OBS_Pert_State)
        ! !USES: 
        use ESMF
        use LIS_coreMod
        use LIS_timeMgrMod
        use LIS_historyMod
        use LIS_dataAssimMod
        use LIS_perturbMod
        use LIS_DAobservationsMod
        use LIS_logmod

        implicit none 

        ! !ARGUMENTS: 
        integer                ::  k
        type(ESMF_State)       ::  OBS_State(LIS_rc%nnest)
        type(ESMF_State)       ::  OBS_Pert_State(LIS_rc%nnest)
        ! 
        ! !DESCRIPTION: 
        !   
        !   This routine completes the runtime initializations and 
        !   creation of data structures required for handling CGLS LAI data.
        !  
        !   The arguments are: 
        !   \begin{description}
        !    \item[k] number of observation state 
        !    \item[OBS\_State]   observation state 
        !    \item[OBS\_Pert\_State] observation perturbations state
        !   \end{description}
        !EOP
        integer                ::  n,i,t,kk,jj
        integer                ::  ftn
        integer                ::  status
        type(ESMF_Field)       ::  obsField(LIS_rc%nnest)
        type(ESMF_Field)       ::  pertField(LIS_rc%nnest)
        type(ESMF_ArraySpec)   ::  intarrspec, realarrspec
        type(ESMF_ArraySpec)   ::  pertArrSpec
        character*100          ::  laiobsdir
        character*100          ::  temp
        real, parameter        ::  minssdev =0.001
        real,  allocatable         ::  ssdev(:)
        character*1            ::  vid(2)
        type(pert_dec_type)    ::  obs_pert
        real, pointer          ::  obs_temp(:,:)
        character*40, allocatable  ::  vname(:)
        real        , allocatable  ::  varmin(:)
        real        , allocatable  ::  varmax(:)
        real, allocatable          :: xrange(:), cdf(:)
        character*100          :: modelcdffile(LIS_rc%nnest)
        character*100          :: obscdffile(LIS_rc%nnest)
        integer                :: c,r
        integer                :: ngrid

        allocate(CGLSlai_struc(LIS_rc%nnest))

        call ESMF_ArraySpecSet(intarrspec,rank=1,typekind=ESMF_TYPEKIND_I4,&
             rc=status)
        call LIS_verify(status)

        call ESMF_ArraySpecSet(realarrspec,rank=1,typekind=ESMF_TYPEKIND_R4,&
             rc=status)
        call LIS_verify(status)

        call ESMF_ArraySpecSet(pertArrSpec,rank=2,typekind=ESMF_TYPEKIND_R4,&
             rc=status)
        call LIS_verify(status)

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI data directory:",&
             rc=status)
        do n=1,LIS_rc%nnest
            call ESMF_ConfigGetAttribute(LIS_config,laiobsdir,&
                 rc=status)
            call LIS_verify(status, 'CGLS LAI data directory: is missing')

            call ESMF_AttributeSet(OBS_State(n),"Data Directory",&
                 laiobsdir, rc=status)
            call LIS_verify(status)
        enddo

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI apply QC flags:",&
             rc=status)
        do n=1,LIS_rc%nnest
            call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%qcflag,&
                 rc=status)
            call LIS_verify(status, 'CGLS LAI apply QC flags: is missing')
        enddo


        !-----------------------------------------------------------------------------
        !  CGLS LAI grid definition
        !-----------------------------------------------------------------------------

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI is resampled:",&
             rc=status)
        do n=1,LIS_rc%nnest
            call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%isresampled,&
                 rc=status)
            call LIS_verify(status, 'CGLS LAI is resampled: is missing')
        enddo

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI spatial resolution:",&
             rc=status)
        do n=1,LIS_rc%nnest
            if (CGLSlai_struc(n)%isresampled.ne.0) then
                call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%spatialres,&
                     rc=status)
                call LIS_verify(status, 'CGLS LAI spatial resolution: is missing')
            endif
        enddo

        do n=1,LIS_rc%nnest
            if (CGLSlai_struc(n)%isresampled.ne.0) then
                call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI lat max:",&
                     rc=status)
                if (status .ne. 0) then
                    CGLSlai_struc(n)%latmax = 90. - 0.5 * CGLSlai_struc(n)%spatialres
                else
                    call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%latmax,&
                         rc=status)
                endif

                call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI lat min:",&
                     rc=status)
                if (status .ne. 0) then
                    CGLSlai_struc(n)%latmin = -90. + 0.5 * CGLSlai_struc(n)%spatialres
                else
                    call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%latmin,&
                         rc=status)
                endif
                call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI lon max:",&
                     rc=status)
                if (status .ne. 0) then
                    CGLSlai_struc(n)%lonmax = 180. - 0.5 * CGLSlai_struc(n)%spatialres
                else
                    call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%lonmax,&
                         rc=status)
                endif
                call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI lon min:",&
                     rc=status)
                if (status .ne. 0) then
                    CGLSlai_struc(n)%lonmin = -180. + 0.5 * CGLSlai_struc(n)%spatialres
                else
                    call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%lonmin,&
                         rc=status)
                endif

                CGLSlai_struc(n)%dlat = CGLSlai_struc(n)%spatialres
                CGLSlai_struc(n)%dlon = CGLSlai_struc(n)%spatialres
                CGLSlai_struc(n)%nr = nint((CGLSlai_struc(n)%latmax - CGLSlai_struc(n)%latmin)&
                                           / CGLSlai_struc(n)%spatialres) + 1
                CGLSlai_struc(n)%nc = nint((CGLSlai_struc(n)%lonmax - CGLSlai_struc(n)%lonmin)&
                                           / CGLSlai_struc(n)%spatialres) + 1
            else
                CGLSlai_struc(n)%latmax = 80.
                CGLSlai_struc(n)%latmin = -59.9910714285396
                CGLSlai_struc(n)%lonmax= -180.
                CGLSlai_struc(n)%lonmin = 179.991071429063
                CGLSlai_struc(n)%dlat = 0.008928002004371148
                CGLSlai_struc(n)%dlon = 0.008928349985839856
                CGLSlai_struc(n)%nc = 40320
                CGLSlai_struc(n)%nr = 15680
            endif
        enddo


        !-----------------------------------------------------------------------------
        !  CGLS LAI rescaling
        !-----------------------------------------------------------------------------

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI model CDF file:",&
             rc=status)
        do n=1,LIS_rc%nnest
            if(LIS_rc%dascaloption(k).ne."none") then 
                call ESMF_ConfigGetAttribute(LIS_config,modelcdffile(n),rc=status)
                call LIS_verify(status, 'CGLS LAI model CDF file: not defined')
            endif
        enddo

        call ESMF_ConfigFindLabel(LIS_config,"CGLS LAI observation CDF file:",&
             rc=status)
        do n=1,LIS_rc%nnest
            if(LIS_rc%dascaloption(k).ne."none") then 
                call ESMF_ConfigGetAttribute(LIS_config,obscdffile(n),rc=status)
                call LIS_verify(status, 'CGLS LAI observation CDF file: not defined')
            endif
        enddo

        call ESMF_ConfigFindLabel(LIS_config, "CGLS LAI number of bins in the CDF:", rc=status)
        do n=1, LIS_rc%nnest
            if(LIS_rc%dascaloption(k).ne."none") then 
                call ESMF_ConfigGetAttribute(LIS_config,CGLSlai_struc(n)%nbins, rc=status)
                call LIS_verify(status, "CGLS LAI number of bins in the CDF: not defined")
            endif
        enddo

        do n=1,LIS_rc%nnest
            call ESMF_AttributeSet(OBS_State(n),"Data Update Status",&
                 .false., rc=status)
            call LIS_verify(status)

            call ESMF_AttributeSet(OBS_State(n),"Data Update Time",&
                 -99.0, rc=status)
            call LIS_verify(status)

            call ESMF_AttributeSet(OBS_State(n),"Data Assimilate Status",&
                 .false., rc=status)
            call LIS_verify(status)

            call ESMF_AttributeSet(OBS_State(n),"Number Of Observations",&
                 LIS_rc%obs_ngrid(k),rc=status)
            call LIS_verify(status)

        enddo

        write(LIS_logunit,*)&
             '[INFO] read CGLS LAI data specifications'       

        do n=1,LIS_rc%nnest

            allocate(CGLSlai_struc(n)%laiobs1(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
            allocate(CGLSlai_struc(n)%laiobs2(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))

            write(unit=temp,fmt='(i2.2)') 1
            read(unit=temp,fmt='(2a1)') vid

            obsField(n) = ESMF_FieldCreate(arrayspec=realarrspec,&
                 grid=LIS_obsVecGrid(n,k),&
                 name="Observation"//vid(1)//vid(2), rc=status)
            call LIS_verify(status)

            !Perturbations State
            write(LIS_logunit,*) '[INFO] Opening attributes for observations ',&
                 trim(LIS_rc%obsattribfile(k))
            ftn = LIS_getNextUnitNumber()
            open(ftn,file=trim(LIS_rc%obsattribfile(k)),status='old')
            read(ftn,*)
            read(ftn,*) LIS_rc%nobtypes(k)
            read(ftn,*)

            allocate(vname(LIS_rc%nobtypes(k)))
            allocate(varmax(LIS_rc%nobtypes(k)))
            allocate(varmin(LIS_rc%nobtypes(k)))

            do i=1,LIS_rc%nobtypes(k)
                read(ftn,fmt='(a40)') vname(i)
                read(ftn,*) varmin(i),varmax(i)
                write(LIS_logunit,*) '[INFO] ',vname(i),varmin(i),varmax(i)
            enddo
            call LIS_releaseUnitNumber(ftn)   

            allocate(ssdev(LIS_rc%obs_ngrid(k)))

            if(trim(LIS_rc%perturb_obs(k)).ne."none") then 
                allocate(obs_pert%vname(1))
                allocate(obs_pert%perttype(1))
                allocate(obs_pert%ssdev(1))
                allocate(obs_pert%stdmax(1))
                allocate(obs_pert%zeromean(1))
                allocate(obs_pert%tcorr(1))
                allocate(obs_pert%xcorr(1))
                allocate(obs_pert%ycorr(1))
                allocate(obs_pert%ccorr(1,1))

                call LIS_readPertAttributes(1,LIS_rc%obspertAttribfile(k),&
                     obs_pert)

                ! Set obs err to be uniform (will be rescaled later for each grid point). 
                ssdev = obs_pert%ssdev(1)
                CGLSlai_struc(n)%ssdev_inp = obs_pert%ssdev(1)

                pertField(n) = ESMF_FieldCreate(arrayspec=pertArrSpec,&
                     grid=LIS_obsEnsOnGrid(n,k),name="Observation"//vid(1)//vid(2),&
                     rc=status)
                call LIS_verify(status)

                ! initializing the perturbations to be zero 
                call ESMF_FieldGet(pertField(n),localDE=0,farrayPtr=obs_temp,rc=status)
                call LIS_verify(status)
                obs_temp(:,:) = 0 

                call ESMF_AttributeSet(pertField(n),"Perturbation Type",&
                     obs_pert%perttype(1), rc=status)
                call LIS_verify(status)

                if(LIS_rc%obs_ngrid(k).gt.0) then 
                    call ESMF_AttributeSet(pertField(n),"Standard Deviation",&
                         ssdev,itemCount=LIS_rc%obs_ngrid(k),rc=status)
                    call LIS_verify(status)
                endif

                call ESMF_AttributeSet(pertField(n),"Std Normal Max",&
                     obs_pert%stdmax(1), rc=status)
                call LIS_verify(status)

                call ESMF_AttributeSet(pertField(n),"Ensure Zero Mean",&
                     obs_pert%zeromean(1),rc=status)
                call LIS_verify(status)

                call ESMF_AttributeSet(pertField(n),"Temporal Correlation Scale",&
                     obs_pert%tcorr(1),rc=status)
                call LIS_verify(status)

                call ESMF_AttributeSet(pertField(n),"X Correlation Scale",&
                     obs_pert%xcorr(1),rc=status)

                call ESMF_AttributeSet(pertField(n),"Y Correlation Scale",&
                     obs_pert%ycorr(1),rc=status)

                call ESMF_AttributeSet(pertField(n),"Cross Correlation Strength",&
                     obs_pert%ccorr(1,:),itemCount=1,rc=status)

                call ESMF_StateAdd(OBS_Pert_State(n),(/pertField(n)/),rc=status)
                call LIS_verify(status)         

            endif

            deallocate(vname)
            deallocate(varmax)
            deallocate(varmin)
            deallocate(ssdev)   

        enddo

        do n=1,LIS_rc%nnest
            if(LIS_rc%dascaloption(k).ne."none") then 

                call LIS_getCDFattributes(k,modelcdffile(n),&
                     CGLSlai_struc(n)%ntimes, ngrid)

                allocate(ssdev(LIS_rc%obs_ngrid(k)))
                ssdev = obs_pert%ssdev(1)

                allocate(CGLSlai_struc(n)%model_mu(LIS_rc%obs_ngrid(k),&
                     CGLSlai_struc(n)%ntimes))
                allocate(CGLSlai_struc(n)%model_sigma(LIS_rc%obs_ngrid(k),&
                     CGLSlai_struc(n)%ntimes))
                allocate(CGLSlai_struc(n)%obs_mu(LIS_rc%obs_ngrid(k),&
                     CGLSlai_struc(n)%ntimes))
                allocate(CGLSlai_struc(n)%obs_sigma(LIS_rc%obs_ngrid(k),&
                     CGLSlai_struc(n)%ntimes))
                allocate(CGLSlai_struc(n)%model_xrange(&
                     LIS_rc%obs_ngrid(k), CGLSlai_struc(n)%ntimes, &
                     CGLSlai_struc(n)%nbins))
                allocate(CGLSlai_struc(n)%obs_xrange(&
                     LIS_rc%obs_ngrid(k), CGLSlai_struc(n)%ntimes, &
                     CGLSlai_struc(n)%nbins))
                allocate(CGLSlai_struc(n)%model_cdf(&
                     LIS_rc%obs_ngrid(k), CGLSlai_struc(n)%ntimes, &
                     CGLSlai_struc(n)%nbins))
                allocate(CGLSlai_struc(n)%obs_cdf(&
                     LIS_rc%obs_ngrid(k), CGLSlai_struc(n)%ntimes, & 
                     CGLSlai_struc(n)%nbins))

                !----------------------------------------------------------------------------
                ! Read the model and observation CDF data
                !----------------------------------------------------------------------------
                call LIS_readMeanSigmaData(n,k,&
                     CGLSlai_struc(n)%ntimes, & 
                     LIS_rc%obs_ngrid(k), &
                     modelcdffile(n), &
                     "LAI",&
                     CGLSlai_struc(n)%model_mu,&
                     CGLSlai_struc(n)%model_sigma)

                call LIS_readMeanSigmaData(n,k,&
                     CGLSlai_struc(n)%ntimes, & 
                     LIS_rc%obs_ngrid(k), &
                     obscdffile(n), &
                     "LAI",&
                     CGLSlai_struc(n)%obs_mu,&
                     CGLSlai_struc(n)%obs_sigma)

                call LIS_readCDFdata(n,k,&
                     CGLSlai_struc(n)%nbins,&
                     CGLSlai_struc(n)%ntimes, & 
                     LIS_rc%obs_ngrid(k), &
                     modelcdffile(n), &
                     "LAI",&
                     CGLSlai_struc(n)%model_xrange,&
                     CGLSlai_struc(n)%model_cdf)

                call LIS_readCDFdata(n,k,&
                     CGLSlai_struc(n)%nbins,&
                     CGLSlai_struc(n)%ntimes, & 
                     LIS_rc%obs_ngrid(k), &
                     obscdffile(n), &
                     "LAI",&
                     CGLSlai_struc(n)%obs_xrange,&
                     CGLSlai_struc(n)%obs_cdf)

                if(CGLSlai_struc(n)%useSsdevScal.eq.1) then 
                    if(CGLSlai_struc(n)%ntimes.eq.1) then 
                        jj = 1
                    else
                        jj = LIS_rc%mo
                    endif
                    do t=1,LIS_rc%obs_ngrid(k)
                        if(CGLSlai_struc(n)%obs_sigma(t,jj).ne.LIS_rc%udef) then 
                            print*, ssdev(t),CGLSlai_struc(n)%model_sigma(t,jj),&
                                 CGLSlai_struc(n)%obs_sigma(t,jj)
                            if(CGLSlai_struc(n)%obs_sigma(t,jj).ne.0) then 
                                ssdev(t) = ssdev(t)*CGLSlai_struc(n)%model_sigma(t,jj)/&
                                     CGLSlai_struc(n)%obs_sigma(t,jj)
                            endif

                            if(ssdev(t).lt.minssdev) then 
                                ssdev(t) = minssdev
                            endif
                        endif
                    enddo
                endif

                if(LIS_rc%obs_ngrid(k).gt.0) then 
                    call ESMF_AttributeSet(pertField(n),"Standard Deviation",&
                         ssdev,itemCount=LIS_rc%obs_ngrid(k),rc=status)
                    call LIS_verify(status)
                endif

                deallocate(ssdev)

            endif
        enddo

        do n=1,LIS_rc%nnest
            ! scale factor for unpacking the data
            CGLSlai_struc(n)%scale = 0.033333

            if(LIS_rc%lis_obs_map_proj(k).ne."latlon") then
                write(LIS_logunit,*)&
                     '[ERROR] The CGLS LAI module only works with latlon projection'       
                call LIS_endrun
            endif

            CGLSlai_struc(n)%gridDesci(1) = 0  ! regular lat-lon grid
            CGLSlai_struc(n)%gridDesci(2) = CGLSlai_struc(n)%nc
            CGLSlai_struc(n)%gridDesci(3) = CGLSlai_struc(n)%nr 
            CGLSlai_struc(n)%gridDesci(4) = CGLSlai_struc(n)%latmax
            CGLSlai_struc(n)%gridDesci(5) = CGLSlai_struc(n)%lonmin
            CGLSlai_struc(n)%gridDesci(6) = 128
            CGLSlai_struc(n)%gridDesci(7) = CGLSlai_struc(n)%latmin
            CGLSlai_struc(n)%gridDesci(8) = CGLSlai_struc(n)%lonmax
            CGLSlai_struc(n)%gridDesci(9) = CGLSlai_struc(n)%dlat
            CGLSlai_struc(n)%gridDesci(10) = CGLSlai_struc(n)%dlon
            CGLSlai_struc(n)%gridDesci(20) = 64

            CGLSlai_struc(n)%mi = CGLSlai_struc(n)%nc*CGLSlai_struc(n)%nr

            !-----------------------------------------------------------------------------
            !   Use interpolation if LIS is running finer than native resolution. 
            !-----------------------------------------------------------------------------
            if(LIS_rc%obs_gridDesc(k,10).lt.CGLSlai_struc(n)%dlon) then 

                allocate(CGLSlai_struc(n)%rlat(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%rlon(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%n11(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%n12(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%n21(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%n22(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%w11(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%w12(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%w21(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))
                allocate(CGLSlai_struc(n)%w22(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k)))

                write(LIS_logunit,*)&
                     '[INFO] create interpolation input for CGLS LAI'       

                call bilinear_interp_input_withgrid(CGLSlai_struc(n)%gridDesci(:), &
                     LIS_rc%obs_gridDesc(k,:),&
                     LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k),&
                     CGLSlai_struc(n)%rlat, CGLSlai_struc(n)%rlon,&
                     CGLSlai_struc(n)%n11, CGLSlai_struc(n)%n12, &
                     CGLSlai_struc(n)%n21, CGLSlai_struc(n)%n22, &
                     CGLSlai_struc(n)%w11, CGLSlai_struc(n)%w12, &
                     CGLSlai_struc(n)%w21, CGLSlai_struc(n)%w22)
            else

                allocate(CGLSlai_struc(n)%n11(&
                     CGLSlai_struc(n)%nc*CGLSlai_struc(n)%nr))

                write(LIS_logunit,*)&
                     '[INFO] create upscaling input for CGLS LAI'       

                call upscaleByAveraging_input(CGLSlai_struc(n)%gridDesci(:),&
                     LIS_rc%obs_gridDesc(k,:),&
                     CGLSlai_struc(n)%nc*CGLSlai_struc(n)%nr, &
                     LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k), CGLSlai_struc(n)%n11)

                write(LIS_logunit,*)&
                     '[INFO] finished creating upscaling input for CGLS LAI'       
            endif

            call LIS_registerAlarm("CGLS LAI read alarm",&
                 86400.0, 86400.0)

            CGLSlai_struc(n)%startMode = .true. 

            call ESMF_StateAdd(OBS_State(n),(/obsField(n)/),rc=status)
            call LIS_verify(status)

        enddo
    end subroutine CGLSlai_setup
end module CGLSlai_Mod
