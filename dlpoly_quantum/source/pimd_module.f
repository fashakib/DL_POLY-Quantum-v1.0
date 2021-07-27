      module pimd_module
      
c**********************************************************************
c     
c     dl_poly_classic module for defining path integral variables and
c     arrays
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      use setup_module,  only : mspimd,nrite,boltz,hbar,mxbuff,ntherm,
     x                          npuni,nbeads,nchain
      use config_module, only : cell,rcell,weight,xxx,yyy,zzz,buffer,
     x                          vxx,vyy,vzz,fxx,fyy,fzz
      use utility_module, only : invert,puni,gauss
      use error_module,   only : error
      
      implicit none

      integer, parameter :: pimd_tag=28173  ! mpi message tag
      
      integer, allocatable :: ltpbak(:),lexbak(:,:)
      integer, allocatable :: lsibak(:),lsabak(:),ltgbak(:)
      real(8), allocatable :: chgbak(:)
      real(8), allocatable :: xxxbak(:),yyybak(:),zzzbak(:)
      real(8), allocatable :: fxxbak(:),fyybak(:),fzzbak(:)
      real(8), allocatable, save :: zmass(:)
      real(8), allocatable, save :: uxx(:),uyy(:),uzz(:)
      real(8), allocatable, save :: pxx(:),pyy(:),pzz(:)
      real(8), allocatable, save :: wxx(:),wyy(:),wzz(:)
      real(8), allocatable, save :: etx(:,:),ety(:,:),etz(:,:)
      real(8), allocatable, save :: pcx(:,:),pcy(:,:),pcz(:,:)
      
      public alloc_pimd_arrays,dealloc_pimd_arrays
      public quantum_energy,ring_forces,stage_mass
      public read_thermostats,write_thermostats
      public stage_coords,stage_momenta,stage_forces
      public unstage_coords,unstage_momenta,unstage_forces
      public read_rnd_cfg,save_rnd_cfg
      
      contains
      
      subroutine alloc_pimd_arrays(idnode,mxnode)
      
c**********************************************************************
c     
c     dl_poly_classic routine to allocate arrays for path integral 
c     molecular dynamics
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************

      implicit none

      logical safe
      integer, intent(in) :: idnode,mxnode
      integer, dimension(1:12) :: fail

      safe=.true.

c     allocate arrays
      
      fail(:)=0
      
      if(nbeads.gt.1)then
        allocate (zmass(1:mspimd),       stat=fail(1))
        allocate (etx(1:nchain,1:mspimd),stat=fail(2))
        allocate (ety(1:nchain,1:mspimd),stat=fail(3))
        allocate (etz(1:nchain,1:mspimd),stat=fail(4))
        allocate (pcx(1:nchain,1:mspimd),stat=fail(5))
        allocate (pcy(1:nchain,1:mspimd),stat=fail(6))
        allocate (pcz(1:nchain,1:mspimd),stat=fail(7))
        allocate (uxx(1:mspimd),uyy(1:mspimd),stat=fail(8))
        allocate (uzz(1:mspimd),pxx(1:mspimd),stat=fail(9))
        allocate (pyy(1:mspimd),pzz(1:mspimd),stat=fail(10))
        allocate (wxx(1:mspimd),wyy(1:mspimd),stat=fail(11))
        allocate (wzz(1:mspimd),stat=fail(12))
      endif
      
      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,534)
      
      end subroutine alloc_pimd_arrays
      
      subroutine dealloc_pimd_arrays(idnode,mxnode)
      
c**********************************************************************
c     
c     dl_poly_classic routine to deallocate arrays for path integral 
c     molecular dynamics
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none

      logical safe
      integer, intent(in) :: idnode,mxnode
      integer, dimension(1:2) :: fail
      
      fail(:)=0
      safe=.true.
      
      if(nbeads.gt.1)then
        deallocate(zmass,etx,ety,etz,pcx,pcy,pcz,      stat=fail(1))
        deallocate(uxx,uyy,uzz,pxx,pyy,pzz,wxx,wyy,wzz,stat=fail(2))
      endif
      
      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,535)
        
      end subroutine dealloc_pimd_arrays
      
      subroutine pimd_init
     x  (idnode,mxnode,natms,keyres,keyens,temp,sigma,engke,strkin,uuu)
      
c**********************************************************************
c     
c     dl_poly_classic routine to initialise a pimd simulation
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms,keyres,keyens
      integer i,j,k,iatm0,iatm1
      real(8), intent(in) :: temp,sigma
      real(8) engke,tmpscl,tmpold
      real(8) strkin(9),uuu(102)
      
      iatm0=nbeads*((idnode*natms)/mxnode)
      iatm1=nbeads*(((idnode+1)*natms)/mxnode)
      
c     initialise pimd masses
      
      call stage_mass(idnode,mxnode,natms)
      
c     initialise staged coordinates
      
      call stage_coords(idnode,mxnode,natms)
      
      if(keyres.eq.0)then
        
c     initialise pimd thermostats
        
        do i=1,mspimd
          
          do j=1,nchain
            
            etx(j,i)=0.d0
            ety(j,i)=0.d0
            etz(j,i)=0.d0
            pcx(j,i)=0.d0
            pcy(j,i)=0.d0
            pcz(j,i)=0.d0
            
          enddo
          
        enddo
        
c     set starting momenta
        
        call gauss(natms*nbeads,vxx,vyy,vzz)
        
c     initialise staged momenta
        
        call stage_momenta(idnode,mxnode,natms)
        
c     reset centre of mass momentum and system temperature
        
        call reset_pimd_momenta(idnode,mxnode,natms,sigma)

c     restore unstaged velocities

        call unstage_momenta(idnode,mxnode,natms)
        
      else
        
c     restore staged momenta for restart
        
        call stage_momenta(idnode,mxnode,natms)
        
c     read pimd thermostats

        call read_thermostats(idnode,mxnode,natms,tmpold)
        if(keyens.eq.41)then
           call read_rnd_cfg(idnode,mxnode,uuu)
        endif
        
      endif

c     rescale momenta and thermostats for keyres=2
      
      if(keyres.eq.2)then

        tmpscl=sqrt(temp/tmpold)

        do i=1,iatm1-iatm0

          pxx(i)=pxx(i)*tmpscl
          pyy(i)=pyy(i)*tmpscl
          pzz(i)=pzz(i)*tmpscl

        enddo

        do i=1,mspimd
          
          do j=1,nchain
            
            etx(j,i)=0.d0
            ety(j,i)=0.d0
            etz(j,i)=0.d0
            pcx(j,i)=pcx(j,i)*tmpscl
            pcy(j,i)=pcy(j,i)*tmpscl
            pcz(j,i)=pcz(j,i)*tmpscl
            
          enddo
          
        enddo
        
c     restore unstaged velocities

        call unstage_momenta(idnode,mxnode,natms)
        
      endif
        
c     calculate kinetic tensor and energy
      
      strkin(:)=0.d0
      do i=1,iatm1-iatm0
        
        strkin(1)=strkin(1)+pxx(i)*pxx(i)/zmass(i)
        strkin(2)=strkin(2)+pxx(i)*pyy(i)/zmass(i)
        strkin(3)=strkin(3)+pxx(i)*pzz(i)/zmass(i)
        strkin(5)=strkin(5)+pyy(i)*pyy(i)/zmass(i)
        strkin(6)=strkin(6)+pyy(i)*pzz(i)/zmass(i)
        strkin(9)=strkin(9)+pzz(i)*pzz(i)/zmass(i)
        
      enddo
      
      strkin(4)=strkin(2)
      strkin(7)=strkin(3)
      strkin(8)=strkin(6)
      
      if(mxnode.gt.1)call gdsum(strkin,9,buffer)
      engke=0.5d0*(strkin(1)+strkin(5)+strkin(9))
      
      return      
      end subroutine pimd_init
      
      subroutine stage_mass(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly_classic routine to set masses for staging coordinates
c     
c     copyright - daresbury laboratory
c     author    - w.smith august 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      real(8) rmu

      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      rmu=1.d0
      
      do k=1,nbeads
        
        do i=iatm0,iatm1
          
          zmass((i-iatm0)*nbeads+k)=rmu*weight((k-1)*natms+i)
          
        enddo
        
        rmu=dble(k+1)/dble(k)
        
      enddo
      
      end subroutine stage_mass
      
      subroutine quantum_energy
     x  (idnode,mxnode,natms,temp,engke,engcfg,engrng,engqpi,
     x  engqvr,qmsrgr)
      
c**********************************************************************
c     
c     dl_poly_classic routine for calculating the quantum energy using
c     the virial energy estimator
c     
c     copyright - daresbury laboratory
c     author    - w.smith july 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in)  :: idnode,mxnode,natms
      real(8), intent(in)  :: temp,engke,engcfg,engrng
      real(8), intent(out) :: engqpi,engqvr,qmsrgr
      
      integer i,j,k,m,n,fail,iatm0,iatm1,nnn
      real(8) dxx,dyy,dzz,cxx,cyy,czz,sxx,syy,szz,sprcon,det
      real(8), allocatable :: rxx(:),ryy(:),rzz(:)
      
      fail=0
      allocate (rxx(nbeads),ryy(nbeads),rzz(nbeads),stat=fail)
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
c     fixed contributions to spring constant
      
      sprcon=0.5d0*dble(nbeads)*(boltz*temp/hbar)**2
      
c     initialise virial energy estimator and mean-square radius of gyration
      
      engqvr=0.d0
      qmsrgr=0.d0
      
c     inverse of cell matrix
      
      call invert(cell,rcell,det)
      
c     calculate ring virial and ring centroid
      
      do i=iatm0,iatm1
        
c     determine centroid of ring
        
        cxx=0.d0
        cyy=0.d0
        czz=0.d0
        rxx(1)=0.d0
        ryy(1)=0.d0
        rzz(1)=0.d0
        
        nnn=natms
        
        do k=2,nbeads
          
          dxx=xxx(nnn+i)-xxx(i)
          dyy=yyy(nnn+i)-yyy(i)
          dzz=zzz(nnn+i)-zzz(i)
          sxx=dxx*rcell(1)+dyy*rcell(4)+dzz*rcell(7)
          syy=dxx*rcell(2)+dyy*rcell(5)+dzz*rcell(8)
          szz=dxx*rcell(3)+dyy*rcell(6)+dzz*rcell(9)
          sxx=sxx-anint(sxx)
          syy=syy-anint(syy)
          szz=szz-anint(szz)
          dxx=sxx*cell(1)+syy*cell(4)+szz*cell(7)
          dyy=sxx*cell(2)+syy*cell(5)+szz*cell(8)
          dzz=sxx*cell(3)+syy*cell(6)+szz*cell(9)
          cxx=cxx+dxx
          cyy=cyy+dyy
          czz=czz+dzz
          rxx(k)=dxx
          ryy(k)=dyy
          rzz(k)=dzz
          
          nnn=nnn+natms
          
        enddo
        
        cxx=cxx/dble(nbeads)
        cyy=cyy/dble(nbeads)
        czz=czz/dble(nbeads)
        
c     virial energy estimator calculation
        
        nnn=0
        
        do k=1,nbeads
          
          m=k-1
          if(k.eq.1)m=nbeads
          n=k+1
          if(k.eq.nbeads)n=1
          
          dxx=rxx(k)-cxx
          dyy=ryy(k)-cyy
          dzz=rzz(k)-czz
          
c     calculate mean-square radius of gyration
          
          qmsrgr=qmsrgr+(dxx**2+dyy**2+dzz**2)
          
c     calculate virial energy estimator
          
          engqvr=engqvr+
     x      dxx*(fxx(nnn+i)+2.d0*sprcon*weight(i)*
     x      ((rxx(k)-rxx(m))+(rxx(k)-rxx(n))))+
     x      dyy*(fyy(nnn+i)+2.d0*sprcon*weight(i)*
     x      ((ryy(k)-ryy(m))+(ryy(k)-ryy(n))))+
     x      dzz*(fzz(nnn+i)+2.d0*sprcon*weight(i)*
     x      ((rzz(k)-rzz(m))+(rzz(k)-rzz(n))))
          
          nnn=nnn+natms
          
        enddo
        
      enddo
      
      engqvr=-0.5d0*engqvr
      
c     global sum of ring virial and mean-square radius of gyration
      
      if(mxnode.gt.1) then
        
        buffer(1)=engqvr
        buffer(2)=qmsrgr
        
        call gdsum(buffer(1),2,buffer(3))
        
        engqvr=buffer(1)
        qmsrgr=buffer(2)
        
      endif
      
      qmsrgr=qmsrgr/(dble(nbeads)*dble(natms))
      
c     calculate final estimates of quantum energy (standard and virial estimate)
      
      engqpi=engke+engcfg-engrng
      engqvr=engqvr+engke/dble(nbeads)+engcfg
      
      deallocate (rxx,ryy,rzz,stat=fail)

      end subroutine quantum_energy

      subroutine ring_forces
     x  (idnode,mxnode,natms,temp,engrng,virrng,qmsbnd,stress)
      
c**********************************************************************
c     
c     dl_poly_classic routine for calculating polymer ring forces and 
c     primitive energy estimator in path integral molecular dynamics
c     
c     copyright - daresbury laboratory
c     author    - w.smith july 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in)  :: idnode,mxnode,natms
      real(8), intent(in)  :: temp
      real(8), intent(out) :: engrng,virrng,qmsbnd
      real(8), dimension(1:9), intent(inout) :: stress
      integer i,k,m,n,iatm0,iatm1
      real(8) sprcon,dxx,dyy,dzz,sxx,syy,szz,fx,fy,fz,det,rstrss(1:9)
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
c     initialise rinq potential energy and rms bondlength
      
      engrng=0.d0
      qmsbnd=0.d0
      rstrss(:)=0.d0
      
c     fixed contributions to spring constant
      
      sprcon=0.5d0*dble(nbeads)*(boltz*temp/hbar)**2
      
c     inverse of cell matrix
      
      call invert(cell,rcell,det)
      
c     calculate ring polymer energy and forces
      
      n=(nbeads-1)*natms
      
      do k=1,nbeads
        
        m=(k-1)*natms
        
        do i=iatm0,iatm1
          
          dxx=xxx(m+i)-xxx(n+i)
          dyy=yyy(m+i)-yyy(n+i)
          dzz=zzz(m+i)-zzz(n+i)
          
          sxx=dxx*rcell(1)+dyy*rcell(4)+dzz*rcell(7)
          syy=dxx*rcell(2)+dyy*rcell(5)+dzz*rcell(8)
          szz=dxx*rcell(3)+dyy*rcell(6)+dzz*rcell(9)
          sxx=sxx-anint(sxx)
          syy=syy-anint(syy)
          szz=szz-anint(szz)
          dxx=sxx*cell(1)+syy*cell(4)+szz*cell(7)
          dyy=sxx*cell(2)+syy*cell(5)+szz*cell(8)
          dzz=sxx*cell(3)+syy*cell(6)+szz*cell(9)
          
          fx=2.d0*sprcon*weight(i)*dxx
          fy=2.d0*sprcon*weight(i)*dyy
          fz=2.d0*sprcon*weight(i)*dzz
          
          qmsbnd=qmsbnd+(dxx**2+dyy**2+dzz**2)
          engrng=engrng+sprcon*weight(i)*(dxx**2+dyy**2+dzz**2)
          
          fxx(m+i)=fxx(m+i)-fx
          fyy(m+i)=fyy(m+i)-fy
          fzz(m+i)=fzz(m+i)-fz
          
          fxx(n+i)=fxx(n+i)+fx
          fyy(n+i)=fyy(n+i)+fy
          fzz(n+i)=fzz(n+i)+fz
          
          rstrss(1)=rstrss(1)-dxx*fx
          rstrss(2)=rstrss(2)-dxx*fy
          rstrss(3)=rstrss(3)-dxx*fz
          rstrss(5)=rstrss(5)-dyy*fy
          rstrss(6)=rstrss(6)-dyy*fz
          rstrss(9)=rstrss(9)-dzz*fz
          
        enddo
        
        n=(k-1)*natms
        
      enddo
      
      rstrss(4)=rstrss(2)
      rstrss(7)=rstrss(3)
      rstrss(8)=rstrss(6)
      stress(:)=stress(:)+rstrss(:)
      
c     global sum of ring energy and mean-squared bondlength
      
      if(mxnode.gt.1) then
        
        buffer(1)=engrng
        buffer(2)=qmsbnd
        
        call gdsum(buffer(1),2,buffer(3))
        
        engrng=buffer(1)
        qmsbnd=buffer(2)
        
      endif
      
      qmsbnd=qmsbnd/(dble(natms)*dble(nbeads))
      
c     ring virial is 2x ring energy
      
      virrng=2.d0*engrng
      
      end subroutine ring_forces
      
      subroutine read_thermostats(idnode,mxnode,natms,temp)
      
c**********************************************************************
c     
c     dl_poly_classic subroutine for reading pimd thermostats file
c     
c     copyright - daresbury laboratory
c     author    - w.smith sep 2016
c     
c**********************************************************************
      
      implicit none
      
      logical safe
      character*6 name
      integer idnode,mxnode,natms,numatm
      integer i,j,jdnode,jatms,ierr
      integer iatm0,iatm1,kdnode,fail(2)
      real(8) temp,atms,chain,ready(1)
      
      real(8), dimension( : ), allocatable :: axx,ayy,azz
      real(8), dimension( : ), allocatable :: bxx,byy,bzz
      
      name='THEOLD'
      numatm=nbeads*natms
      
      fail(:)=0
      safe=.true.
      
      allocate (axx(mspimd),ayy(mspimd),azz(mspimd), stat=fail(1))
      allocate (bxx(mspimd),byy(mspimd),bzz(mspimd), stat=fail(2))

      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,530)
      
      if(idnode.eq.0)then
        
        open(unit=ntherm,file=name,form='unformatted',status='old')
        read(ntherm)atms,chain,temp
        if(numatm.ne.nint(atms).or.nchain.ne.nint(chain))safe=.false.
        
      endif
      
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,523)
      
      iatm0=nbeads*((idnode*natms)/mxnode)
      iatm1=nbeads*(((idnode+1)*natms)/mxnode)

c     outer loop over thermostat chains
      
      do j=1,nchain
        
        jatms=iatm1-iatm0
        ready(1)=dble(jatms)
      
c     data is read by processor 0
        
        if(idnode.eq.0)then
          
          do jdnode=0,mxnode-1
            
            if(jdnode.gt.0)then
              
              call csend(pimd_tag,ready,1,jdnode,ierr)
              call crecv(pimd_tag,ready,1)
              jatms=nint(ready(1))
              
            endif
            
            do i=1,jatms
              
              read(ntherm)axx(i),ayy(i),azz(i),bxx(i),byy(i),bzz(i)
              
            enddo
            
            if(jdnode.eq.0)then
              
c     receive data for processor 0
              
              do i=1,jatms
                
                etx(j,i)=axx(i)
                ety(j,i)=ayy(i)
                etz(j,i)=azz(i)
                pcx(j,i)=bxx(i)
                pcy(j,i)=byy(i)
                pcz(j,i)=bzz(i)
                
              enddo
              
            else
              
              call csend(pimd_tag,axx,jatms,jdnode,ierr)
              call csend(pimd_tag,ayy,jatms,jdnode,ierr)
              call csend(pimd_tag,azz,jatms,jdnode,ierr)

              call csend(pimd_tag,bxx,jatms,jdnode,ierr)
              call csend(pimd_tag,byy,jatms,jdnode,ierr)
              call csend(pimd_tag,bzz,jatms,jdnode,ierr)
              
            endif
            
          enddo
          
        else
          
          call crecv(pimd_tag,ready,1)          
          ready(1)=dble(jatms)
          call csend(pimd_tag,ready,1,0,ierr)
          
          call crecv(pimd_tag,axx,jatms)
          call crecv(pimd_tag,ayy,jatms)
          call crecv(pimd_tag,azz,jatms)
          
          call crecv(pimd_tag,bxx,jatms)
          call crecv(pimd_tag,byy,jatms)
          call crecv(pimd_tag,bzz,jatms)
          
c     receive data for all other processors
          
          do i=1,jatms
            
            etx(j,i)=axx(i)
            ety(j,i)=ayy(i)
            etz(j,i)=azz(i)
            pcx(j,i)=bxx(i)
            pcy(j,i)=byy(i)
            pcz(j,i)=bzz(i)
            
          enddo
          
        endif
        
      enddo
      
      close(ntherm)
      
      deallocate (axx,ayy,azz,bxx,byy,bzz, stat=fail(1))
      
      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,531)
      
      if(mxnode.gt.1)call gsync()
      
      end subroutine read_thermostats
      
      subroutine write_thermostats(idnode,mxnode,natms,temp)
      
c**********************************************************************
c     
c     dl_poly_classic subroutine for writing pimd thermostats file
c     
c     copyright - daresbury laboratory
c     author    - w.smith jul 2016
c     
c**********************************************************************
      
      implicit none
      
      logical safe
      character*6 name
      integer idnode,mxnode,natms,numatm
      integer i,j,jdnode,jatms,ierr
      integer iatm0,iatm1,fail(2)
      real(8) temp,ready(1)
      
      real(8), dimension( : ), allocatable :: axx,ayy,azz
      real(8), dimension( : ), allocatable :: bxx,byy,bzz
      
      name='THENEW'
      numatm=nbeads*natms
      
      fail(:)=0
      safe=.true.
      
      allocate (axx(mspimd),ayy(mspimd),azz(mspimd), stat=fail(1))
      allocate (bxx(mspimd),byy(mspimd),bzz(mspimd), stat=fail(2))
      
      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,532)
      
      if(idnode.eq.0)then
        
        open(unit=ntherm,file=name,form='unformatted',status='replace')
        write(ntherm)dble(numatm),dble(nchain),temp
        
      endif
      
      iatm0=nbeads*((idnode*natms)/mxnode)
      iatm1=nbeads*(((idnode+1)*natms)/mxnode)

c     outer loop over thermostat chains

      do j=1,nchain
        
        jatms=iatm1-iatm0
        ready(1)=dble(jatms)
      
c     load up thermostat data for transfer
      
        do i=1,jatms
          
          axx(i)=etx(j,i)
          ayy(i)=ety(j,i)
          azz(i)=etz(j,i)
          bxx(i)=pcx(j,i)
          byy(i)=pcy(j,i)
          bzz(i)=pcz(j,i)
          
        enddo
        
c     data is written out by processor 0
        
        if(idnode.eq.0)then
          
          do jdnode=0,mxnode-1
            if(jdnode.gt.0)then
              
              call csend(pimd_tag,ready,1,jdnode,ierr)
              call crecv(pimd_tag,ready,1)
              jatms=nint(ready(1))
              
              call crecv(pimd_tag,axx,jatms)
              call crecv(pimd_tag,ayy,jatms)
              call crecv(pimd_tag,azz,jatms)
              
              call crecv(pimd_tag,bxx,jatms)
              call crecv(pimd_tag,byy,jatms)
              call crecv(pimd_tag,bzz,jatms)
              
            endif
            
            do i=1,jatms
              
              write(ntherm)axx(i),ayy(i),azz(i),bxx(i),byy(i),bzz(i)
              
            enddo
            
          enddo
          
        else
          
          call crecv(pimd_tag,ready,1)
          ready(1)=dble(jatms)
          call csend(pimd_tag,ready,1,0,ierr)
          
          call csend(pimd_tag,axx,jatms,0,ierr)
          call csend(pimd_tag,ayy,jatms,0,ierr)
          call csend(pimd_tag,azz,jatms,0,ierr)
          
          call csend(pimd_tag,bxx,jatms,0,ierr)
          call csend(pimd_tag,byy,jatms,0,ierr)
          call csend(pimd_tag,bzz,jatms,0,ierr)
          
        endif
        
      enddo
      
      close(ntherm)
      
      deallocate (axx,ayy,azz,bxx,byy,bzz, stat=fail(1))
      
      if(any(fail.gt.0))safe=.false.
      if(mxnode.gt.1)call gstate(safe)
      if(.not.safe)call error(idnode,533)
      
      if(mxnode.gt.1)call gsync()
      
      end subroutine write_thermostats
      
      subroutine read_rnd_cfg(idnode,mxnode,uuu)
      
c**********************************************************************
c     
c     dl_poly_classic subroutine for reading the parallel random
c     number generator configuration
c
c     copyright - daresbury laboratory
c     author    - w.smith sep 2016
c     
c**********************************************************************
      
      implicit none
      
      logical safe
      character*6 name
      integer idnode,mxnode,i,jdnode,ierr
      real(8) uuu(102),uu0(102),ready(1)
      real(8) dum
      
      name='RNDOLD'
      ready(1)=1.d0

      if(idnode.eq.0)then
        
        open(unit=npuni,file=name,form='unformatted',status='old')
        read(npuni)uuu
        dum=puni(2,uuu)
        
        do jdnode=1,mxnode-1
          
          read(npuni)uu0
          call csend(pimd_tag,ready,1,jdnode,ierr)
          call csend(pimd_tag,uu0,102,jdnode,ierr)

        enddo
        
      else
        
        call crecv(pimd_tag,ready,1)          
        call crecv(pimd_tag,uuu,102)
        dum=puni(2,uuu)
        
      endif
        
      close(npuni)
      
      if(mxnode.gt.1)call gsync()
      
      end subroutine read_rnd_cfg
      
      subroutine save_rnd_cfg(idnode,mxnode,uuu)
      
c**********************************************************************
c     
c     dl_poly_classic subroutine for saving the parallel random
c     number generator configuration
c     
c     copyright - daresbury laboratory
c     author    - w.smith sep 2016
c     
c**********************************************************************
      
      implicit none

      character*6 name
      integer idnode,mxnode,i,jdnode,ierr
      real(8) uuu(102),ready(1)
      real(4) dum
      
      name='RNDNEW'
      ready(1)=0.d0
      
c     data is written out by processor 0
      
      if(idnode.eq.0)then
        
        open(unit=npuni,file=name,form='unformatted',status='replace')
        dum=puni(3,uuu)
        write(npuni)uuu
        
        do jdnode=1,mxnode-1

          call csend(pimd_tag,ready,1,jdnode,ierr)
          call crecv(pimd_tag,uuu,102)
          write(npuni)uuu
          
        enddo
        
      else

        dum=puni(3,uuu)
        call crecv(pimd_tag,ready,1)
        call csend(pimd_tag,uuu,102,0,ierr)
        
      endif
      
      close(npuni)
      
      if(mxnode.gt.1)call gsync()
      
      end subroutine save_rnd_cfg
      
      subroutine stage_coords(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables 
c     for path integral molecular dynamics - coordinate staging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none

      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1

      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      call ring_gather(idnode,mxnode,natms)
      
      do i=iatm0,iatm1
        
        uxx((i-iatm0)*nbeads+1)=xxx(i)
        uyy((i-iatm0)*nbeads+1)=yyy(i)
        uzz((i-iatm0)*nbeads+1)=zzz(i)
        
        uxx((i-iatm0+1)*nbeads)=xxx((nbeads-1)*natms+i)-xxx(i)
        uyy((i-iatm0+1)*nbeads)=yyy((nbeads-1)*natms+i)-yyy(i)
        uzz((i-iatm0+1)*nbeads)=zzz((nbeads-1)*natms+i)-zzz(i)
        
      enddo
      
      do k=2,nbeads-1
        
        do i=iatm0,iatm1
          
          uxx((i-iatm0)*nbeads+k)=xxx((k-1)*natms+i)
     x      -(dble(k-1)*xxx(k*natms+i)+xxx(i))/dble(k)
          uyy((i-iatm0)*nbeads+k)=yyy((k-1)*natms+i)
     x      -(dble(k-1)*yyy(k*natms+i)+yyy(i))/dble(k)
          uzz((i-iatm0)*nbeads+k)=zzz((k-1)*natms+i)
     x      -(dble(k-1)*zzz(k*natms+i)+zzz(i))/dble(k)
            
        enddo
        
      enddo
      
      end subroutine stage_coords
      
      subroutine stage_momenta(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables 
c     for path integral molecular dynamics - momentum staging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      do i=iatm0,iatm1
        
        pxx((i-iatm0)*nbeads+1)=vxx(i)
        pyy((i-iatm0)*nbeads+1)=vyy(i)
        pzz((i-iatm0)*nbeads+1)=vzz(i)
        
        pxx((i-iatm0+1)*nbeads)=vxx((nbeads-1)*natms+i)-vxx(i)
        pyy((i-iatm0+1)*nbeads)=vyy((nbeads-1)*natms+i)-vyy(i)
        pzz((i-iatm0+1)*nbeads)=vzz((nbeads-1)*natms+i)-vzz(i)
          
      enddo
      
      do k=2,nbeads-1
        
        do i=iatm0,iatm1
          
          pxx((i-iatm0)*nbeads+k)=vxx((k-1)*natms+i)
     x      -(dble(k-1)*vxx(k*natms+i)+vxx(i))/dble(k)
          pyy((i-iatm0)*nbeads+k)=vyy((k-1)*natms+i)
     x      -(dble(k-1)*vyy(k*natms+i)+vyy(i))/dble(k)
          pzz((i-iatm0)*nbeads+k)=vzz((k-1)*natms+i)
     x      -(dble(k-1)*vzz(k*natms+i)+vzz(i))/dble(k)
          
        enddo
        
      enddo
      
      do i=1,nbeads*(iatm1-iatm0+1)
        
        pxx(i)=zmass(i)*pxx(i)
        pyy(i)=zmass(i)*pyy(i)
        pzz(i)=zmass(i)*pzz(i)
        
      enddo
      
      end subroutine stage_momenta
      
      subroutine stage_forces(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables 
c     for path integral molecular dynamics - forces staging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      do i=iatm0,iatm1
        
        wxx((i-iatm0)*nbeads+1)=fxx(i)
        wyy((i-iatm0)*nbeads+1)=fyy(i)
        wzz((i-iatm0)*nbeads+1)=fzz(i)
        
      enddo
      
      do k=2,nbeads
        
        do i=iatm0,iatm1
          
          wxx((i-iatm0)*nbeads+1)=
     x      wxx((i-iatm0)*nbeads+1)+fxx((k-1)*natms+i)
          wyy((i-iatm0)*nbeads+1)=
     x      wyy((i-iatm0)*nbeads+1)+fyy((k-1)*natms+i)
          wzz((i-iatm0)*nbeads+1)=
     x      wzz((i-iatm0)*nbeads+1)+fzz((k-1)*natms+i)
          wxx((i-iatm0)*nbeads+k)=fxx((k-1)*natms+i)
     x      +wxx((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          wyy((i-iatm0)*nbeads+k)=fyy((k-1)*natms+i)
     x      +wyy((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          wzz((i-iatm0)*nbeads+k)=fzz((k-1)*natms+i)
     x      +wzz((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          
        enddo
        
      enddo
      
      end subroutine stage_forces
      
      subroutine unstage_coords(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables for 
c     path integral molecular dynamics - coordinate unstaging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      do i=iatm0,iatm1
        
        xxx(i)=uxx((i-iatm0)*nbeads+1)
        yyy(i)=uyy((i-iatm0)*nbeads+1)
        zzz(i)=uzz((i-iatm0)*nbeads+1)
        
        xxx((nbeads-1)*natms+i)=uxx((i-iatm0+1)*nbeads)
     x    +uxx((i-iatm0)*nbeads+1)
        yyy((nbeads-1)*natms+i)=uyy((i-iatm0+1)*nbeads)
     x    +uyy((i-iatm0)*nbeads+1)
        zzz((nbeads-1)*natms+i)=uzz((i-iatm0+1)*nbeads)
     x    +uzz((i-iatm0)*nbeads+1)
        
      enddo
      
      do k=nbeads-1,2,-1
        
        do i=iatm0,iatm1
          
          xxx((k-1)*natms+i)=uxx((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*xxx(k*natms+i)+xxx(i))/dble(k)
          yyy((k-1)*natms+i)=uyy((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*yyy(k*natms+i)+yyy(i))/dble(k)
          zzz((k-1)*natms+i)=uzz((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*zzz(k*natms+i)+zzz(i))/dble(k)
          
        enddo
        
      enddo
      
c     restore coordinate array replication
      
      call pmerge(idnode,mxnode,natms,xxx,yyy,zzz)
      
      call ring_gather(idnode,mxnode,natms)
      
      end subroutine unstage_coords
      
      subroutine unstage_momenta(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables for 
c     path integral molecular dynamics - momentum unstaging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      do i=1,nbeads*(iatm1-iatm0+1)
        
        pxx(i)=pxx(i)/zmass(i)
        pyy(i)=pyy(i)/zmass(i)
        pzz(i)=pzz(i)/zmass(i)
        
      enddo
      
      do i=iatm0,iatm1
        
        vxx(i)=pxx((i-iatm0)*nbeads+1)
        vyy(i)=pyy((i-iatm0)*nbeads+1)
        vzz(i)=pzz((i-iatm0)*nbeads+1)

        vxx((nbeads-1)*natms+i)=pxx((i-iatm0+1)*nbeads)
     x    +pxx((i-iatm0)*nbeads+1)
        vyy((nbeads-1)*natms+i)=pyy((i-iatm0+1)*nbeads)
     x    +pyy((i-iatm0)*nbeads+1)
        vzz((nbeads-1)*natms+i)=pzz((i-iatm0+1)*nbeads)
     x    +pzz((i-iatm0)*nbeads+1)
        
      enddo
      
      do k=nbeads-1,2,-1
        
        do i=iatm0,iatm1
          
          vxx((k-1)*natms+i)=pxx((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*vxx(k*natms+i)+vxx(i))/dble(k)
          vyy((k-1)*natms+i)=pyy((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*vyy(k*natms+i)+vyy(i))/dble(k)
          vzz((k-1)*natms+i)=pzz((i-iatm0)*nbeads+k)
     x      +(dble(k-1)*vzz(k*natms+i)+vzz(i))/dble(k)
          
        enddo
        
      enddo
      
      do i=1,nbeads*(iatm1-iatm0+1)
        
        pxx(i)=pxx(i)*zmass(i)
        pyy(i)=pyy(i)*zmass(i)
        pzz(i)=pzz(i)*zmass(i)
        
      enddo
      
c     restore velocity array replication
      
      call pmerge(idnode,mxnode,natms,vxx,vyy,vzz)
      
      end subroutine unstage_momenta

      subroutine unstage_forces(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for construction of staging variables for 
c     path integral molecular dynamics - forces unstaging
c     
c     copyright - daresbury laboratory
c     author    - w.smith june 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
      do i=iatm0,iatm1
        
        fxx(i)=wxx((i-iatm0)*nbeads+1)
        fyy(i)=wyy((i-iatm0)*nbeads+1)
        fzz(i)=wzz((i-iatm0)*nbeads+1)
        
      enddo
      
      do k=2,nbeads
        
        do i=iatm0,iatm1

          fxx((k-1)*natms+i)=wxx((i-iatm0)*nbeads+k)-
     x      wxx((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          fyy((k-1)*natms+i)=wyy((i-iatm0)*nbeads+k)-
     x      wyy((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          fzz((k-1)*natms+i)=wzz((i-iatm0)*nbeads+k)-
     x      wzz((i-iatm0)*nbeads+k-1)*dble(k-2)/dble(k-1)
          fxx(i)=fxx(i)-fxx((k-1)*natms+i)
          fyy(i)=fyy(i)-fyy((k-1)*natms+i)
          fzz(i)=fzz(i)-fzz((k-1)*natms+i)
          
        enddo
        
      enddo
      
c     restore force array replication
      
      call pmerge(idnode,mxnode,natms,fxx,fyy,fzz)
      
      end subroutine unstage_forces
      
      subroutine pmerge(idnode,mxnode,natms,xxx,yyy,zzz)

c*********************************************************************
c     
c     dl_poly subroutine for merging coordinate arrays across
c     a number of processors pimd version
c     
c     parallel replicated data version
c     
c     copyright - daresbury laboratory
c     author    - w. smith july 2016
c     
c*********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      real(8), intent(inout) :: xxx(nbeads*natms),yyy(nbeads*natms),
     x                          zzz(nbeads*natms)
      integer nsize,ierr,iatm0,iatm1,natm0,natm1
      integer i,j,k,n,jdnode,ndnode
      
      include "comms.inc"
      
      integer status(MPI_STATUS_SIZE), request
      
c     identify atom indices for this processor
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
c     check that buffer is large enough
      
      nsize=nbeads*((natms+mxnode-1)/mxnode)
      if(mxbuff.lt.6*nsize)call error(idnode,47)
      
c     load initial transfer buffer
      
        do k=0,nbeads-1
          do i=iatm0,iatm1
            
            j=3*((i-iatm0)*nbeads+k)
            buffer(j+1)=xxx(k*natms+i)
            buffer(j+2)=yyy(k*natms+i)
            buffer(j+3)=zzz(k*natms+i)
            
          enddo
        enddo
        
      call gsync()
      
c     identity of neighbour node for systolic transfer
      
      jdnode=mod(idnode+1,mxnode)
      
      do n=1,mxnode-1
        
c     identity of node of origin of incoming data
        
        ndnode=mod(idnode+mxnode-n,mxnode)
        
c     identify atom indices for incoming data
        
        natm0=(ndnode*natms)/mxnode+1
        natm1=((ndnode+1)*natms)/mxnode
        
c     systolic data pulse to transfer data
        
        call MPI_IRECV(buffer(3*nsize+1),3*nsize,MPI_DOUBLE_PRECISION,
     x    MPI_ANY_SOURCE,Merge_tag+n,MPI_COMM_WORLD,request,ierr)
        
        call MPI_SEND(buffer(1),3*nsize,MPI_DOUBLE_PRECISION,jdnode,
     x    Merge_tag+n,MPI_COMM_WORLD,ierr)
        
        call MPI_WAIT(request,status,ierr)
        
c     merge the incoming data into current arrays
        
        do k=0,nbeads-1
          do i=natm0,natm1
            
            j=3*((i-natm0)*nbeads+k+nsize)
            xxx(k*natms+i)=buffer(j+1)
            yyy(k*natms+i)=buffer(j+2)
            zzz(k*natms+i)=buffer(j+3)
            
          enddo
        enddo
        
c     shift new data to start of buffer
        
        do i=1,3*nsize
          
          buffer(i)=buffer(3*nsize+i)
          
        enddo
        
      enddo
      
      end subroutine pmerge
      
      subroutine reset_pimd_momenta(idnode,mxnode,natms,sigma)
      
c**********************************************************************
c     
c     dl_poly classic routine for zeroing momentum of pimd system
c     and setting the system temperature for path integral molecular
c     dynamics
c     
c     copyright - daresbury laboratory
c     author    - w.smith july 2016
c     
c**********************************************************************
      
      implicit none
      
      integer, intent(in) :: idnode,mxnode,natms
      real(8), intent(in) :: sigma
      integer i,iatm0,iatm1
      real(8) pmx,pmy,pmz,engke,tscale,ratms
      
      ratms=dble(nbeads)*dble(natms)
      iatm0=(idnode*natms)/mxnode
      iatm1=((idnode+1)*natms)/mxnode
      
c     calculate the net system momentum
      
      pmx=0.d0
      pmy=0.d0
      pmz=0.d0
      
      do i=1,(iatm1-iatm0)*nbeads
            
        pmx=pmx+pxx(i)
        pmy=pmy+pyy(i)
        pmz=pmz+pzz(i)
        
      enddo
      
      buffer(1)=pmx
      buffer(2)=pmy
      buffer(3)=pmz
      call gdsum(buffer(1),3,buffer(4))
      pmx=buffer(1)/ratms
      pmy=buffer(2)/ratms
      pmz=buffer(3)/ratms
      
c     zero net momentum and calculate system kinetic energy
      
      engke=0.d0
      
      do i=1,(iatm1-iatm0)*nbeads
        
        pxx(i)=pxx(i)-pmx
        pyy(i)=pyy(i)-pmy
        pzz(i)=pzz(i)-pmz
        engke=engke+(pxx(i)**2+pyy(i)**2+pzz(i)**2)/zmass(i)
        
      enddo
      
      buffer(1)=engke
      call gdsum(buffer(1),1,buffer(2))
      engke=0.5d0*buffer(1)
      
c     scale momenta to temperature
      
      tscale=sqrt(sigma/engke)
      
      do i=1,(iatm1-iatm0)*nbeads
        
        pxx(i)=tscale*pxx(i)
        pyy(i)=tscale*pyy(i)
        pzz(i)=tscale*pzz(i)
        
      enddo
      
      end subroutine reset_pimd_momenta
      
      subroutine ring_gather(idnode,mxnode,natms)
      
c**********************************************************************
c     
c     dl_poly classic routine for converting pimd bead ring into a
c     contiguized form in systems with periodic boundary conditions
c     
c     copyright - daresbury laboratory
c     author    - w.smith aug 2016
c     
c**********************************************************************

      integer, intent(in) :: idnode,mxnode,natms
      integer i,k,iatm0,iatm1,nnn
      real(8) dxx,dyy,dzz,sxx,syy,szz,det
      
      iatm0=(idnode*natms)/mxnode+1
      iatm1=((idnode+1)*natms)/mxnode
      
c     inverse of cell matrix
      
      call invert(cell,rcell,det)
      
c     ensure first bead is in periodic cell
      
      do i=iatm0,iatm1
        
        sxx=xxx(i)*rcell(1)+yyy(i)*rcell(4)+zzz(i)*rcell(7)
        syy=xxx(i)*rcell(2)+yyy(i)*rcell(5)+zzz(i)*rcell(8)
        szz=xxx(i)*rcell(3)+yyy(i)*rcell(6)+zzz(i)*rcell(9)
        sxx=sxx-anint(sxx)
        syy=syy-anint(syy)
        szz=szz-anint(szz)
        xxx(i)=sxx*cell(1)+syy*cell(4)+szz*cell(7)
        yyy(i)=sxx*cell(2)+syy*cell(5)+szz*cell(8)
        zzz(i)=sxx*cell(3)+syy*cell(6)+szz*cell(9)
        
      enddo
        
c     ensure remaining beads make an unbroken ring

      nnn=0
      
      do k=2,nbeads
        
        do i=iatm0,iatm1
          
          dxx=xxx(nnn+i)-xxx(i)
          dyy=yyy(nnn+i)-yyy(i)
          dzz=zzz(nnn+i)-zzz(i)
          sxx=dxx*rcell(1)+dyy*rcell(4)+dzz*rcell(7)
          syy=dxx*rcell(2)+dyy*rcell(5)+dzz*rcell(8)
          szz=dxx*rcell(3)+dyy*rcell(6)+dzz*rcell(9)
          sxx=sxx-anint(sxx)
          syy=syy-anint(syy)
          szz=szz-anint(szz)
          dxx=sxx*cell(1)+syy*cell(4)+szz*cell(7)
          dyy=sxx*cell(2)+syy*cell(5)+szz*cell(8)
          dzz=sxx*cell(3)+syy*cell(6)+szz*cell(9)
          xxx(nnn+i)=xxx(i)+dxx
          yyy(nnn+i)=yyy(i)+dyy
          zzz(nnn+i)=zzz(i)+dzz
          
        enddo

        nnn=nnn+natms
        
      enddo
      
      end subroutine ring_gather
      
      end module pimd_module
