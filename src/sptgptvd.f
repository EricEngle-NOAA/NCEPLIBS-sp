C> @file
C>
C> Transform spectral vector to station points
C> @author IREDELL @date 96-02-29

C> THIS SUBPROGRAM PERFORMS A SPHERICAL TRANSFORM
C> FROM SPECTRAL COEFFICIENTS OF DIVERGENCES AND CURLS
C> TO SPECIFIED SETS OF STATION POINT VECTORS AND THEIR
C> GRADIENTS ON THE GLOBE.
C> <pre>
C>             DP=(D(UP)/DLON+D(VP*CLAT)/DLAT)/(R*CLAT)
C>             ZP=(D(VP)/DLON-D(UP*CLAT)/DLAT)/(R*CLAT)
C>             UXP=D(UP*CLAT)/DLON/(R*CLAT)
C>             VXP=D(VP*CLAT)/DLON/(R*CLAT)
C>             UYP=D(UP*CLAT)/DLAT/R
C>             VYP=D(VP*CLAT)/DLAT/R
C> </pre>
C> THE WAVE-SPACE CAN BE EITHER TRIANGULAR OR RHOMBOIDAL.
C> THE WAVE AND POINT FIELDS MAY HAVE GENERAL INDEXING,
C> BUT EACH WAVE FIELD IS IN SEQUENTIAL 'IBM ORDER',
C> I.E. WITH ZONAL WAVENUMBER AS THE SLOWER INDEX.
C> THE TRANSFORMS ARE ALL MULTIPROCESSED OVER STATIONS.
C> TRANSFORM SEVERAL FIELDS AT A TIME TO IMPROVE VECTORIZATION.
C> SUBPROGRAM CAN BE CALLED FROM A MULTIPROCESSING ENVIRONMENT.
C>
C> PROGRAM HISTORY LOG:
C> -  96-02-29  IREDELL
C> - 1998-12-15  IREDELL  OPENMP DIRECTIVES INSERTED
C> - 1999-08-18  IREDELL  OPENMP DIRECTIVE TYPO FIXED 
C>
C> @param IROMB    - INTEGER SPECTRAL DOMAIN SHAPE
C>                (0 FOR TRIANGULAR, 1 FOR RHOMBOIDAL)
C> @param MAXWV    - INTEGER SPECTRAL TRUNCATION
C> @param KMAX     - INTEGER NUMBER OF FIELDS TO TRANSFORM.
C> @param NMAX     - INTEGER NUMBER OF STATION POINTS TO RETURN
C> @param KWSKIP   - INTEGER SKIP NUMBER BETWEEN WAVE FIELDS
C>                (DEFAULTS TO (MAXWV+1)*((IROMB+1)*MAXWV+2) IF KWSKIP=0)
C> @param KGSKIP   - INTEGER SKIP NUMBER BETWEEN STATION POINT SETS
C>                (DEFAULTS TO NMAX IF KGSKIP=0)
C> @param NRSKIP   - INTEGER SKIP NUMBER BETWEEN STATION LATS AND LONS
C>                (DEFAULTS TO 1 IF NRSKIP=0)
C> @param NGSKIP   - INTEGER SKIP NUMBER BETWEEN STATION POINTS
C>                (DEFAULTS TO 1 IF NGSKIP=0)
C> @param RLAT     - REAL (*) STATION LATITUDES IN DEGREES
C> @param RLON     - REAL (*) STATION LONGITUDES IN DEGREES
C> @param WAVED    - REAL (*) WAVE DIVERGENCE FIELDS
C> @param WAVEZ    - REAL (*) WAVE VORTICITY FIELDS
C> @param DP       - REAL (*) STATION POINT DIVERGENCE SETS
C> @param ZP       - REAL (*) STATION POINT VORTICITY SETS
C> @param UP       - REAL (*) STATION POINT U-WIND SETS
C> @param VP       - REAL (*) STATION POINT V-WIND SETS
C> @param UXP      - REAL (*) STATION POINT U-WIND X-GRADIENT SETS
C> @param VXP      - REAL (*) STATION POINT V-WIND X-GRADIENT SETS
C> @param UYP      - REAL (*) STATION POINT U-WIND Y-GRADIENT SETS
C> @param VYP      - REAL (*) STATION POINT V-WIND Y-GRADIENT SETS
C>
C> SUBPROGRAMS CALLED:
C>  - SPWGET       GET WAVE-SPACE CONSTANTS
C>  - SPLEGEND     COMPUTE LEGENDRE POLYNOMIALS
C>  - SPSYNTH      SYNTHESIZE FOURIER FROM SPECTRAL
C>  - SPDZ2UV      COMPUTE WINDS FROM DIVERGENCE AND VORTICITY
C>  - SPGRADX      COMPUTE X-GRADIENT IN FOURIER SPACE
C>  - SPFFTPT      COMPUTE FOURIER TRANSFORM TO GRIDPOINTS
      SUBROUTINE SPTGPTVD(IROMB,MAXWV,KMAX,NMAX,
     &                    KWSKIP,KGSKIP,NRSKIP,NGSKIP,
     &                    RLAT,RLON,WAVED,WAVEZ,
     &                    DP,ZP,UP,VP,UXP,VXP,UYP,VYP)

      REAL RLAT(*),RLON(*),WAVED(*),WAVEZ(*)
      REAL DP(*),ZP(*),UP(*),VP(*),UXP(*),VXP(*),UYP(*),VYP(*)
      REAL EPS((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EPSTOP(MAXWV+1)
      REAL ENN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL ELONN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL EON((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EONTOP(MAXWV+1)
      INTEGER MP(4*KMAX)
      REAL W((MAXWV+1)*((IROMB+1)*MAXWV+2)/2*2,4*KMAX)
      REAL WTOP(2*(MAXWV+1),4*KMAX)
      REAL PLN((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),PLNTOP(MAXWV+1)
      REAL F(2*MAXWV+2,2,6*KMAX),G(6*KMAX)
      PARAMETER(PI=3.14159265358979)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  CALCULATE PRELIMINARY CONSTANTS
      CALL SPWGET(IROMB,MAXWV,EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP)
      MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
      MXTOP=MAXWV+1
      MDIM=2*MX
      IDIM=2*MAXWV+2
      KW=KWSKIP
      KG=KGSKIP
      NR=NRSKIP
      NG=NGSKIP
      IF(KW.EQ.0) KW=2*MX
      IF(KG.EQ.0) KG=NMAX
      IF(NR.EQ.0) NR=1
      IF(NG.EQ.0) NG=1
      MP(1:2*KMAX)=0
      MP(2*KMAX+1:4*KMAX)=1
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  CALCULATE SPECTRAL WINDS
C$OMP PARALLEL DO PRIVATE(KWS,KD,KZ,KU,KV)
      DO K=1,KMAX
        KWS=(K-1)*KW
        KD=0*KMAX+K
        KZ=1*KMAX+K
        KU=2*KMAX+K
        KV=3*KMAX+K
        DO I=1,2*MX
          W(I,KD)=WAVED(KWS+I)
          W(I,KZ)=WAVEZ(KWS+I)
        ENDDO
        DO I=1,2*MXTOP
          WTOP(I,KD)=0
          WTOP(I,KZ)=0
        ENDDO
        CALL SPDZ2UV(IROMB,MAXWV,ENN1,ELONN1,EON,EONTOP,
     &               WAVED(KWS+1),WAVEZ(KWS+1),
     &               W(1,KU),W(1,KV),WTOP(1,KU),WTOP(1,KV))
      ENDDO
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  CALCULATE STATION FIELDS
C$OMP PARALLEL DO PRIVATE(KD,KZ,KU,KV,KUX,KVX,SLAT1,CLAT1)
C$OMP&            PRIVATE(PLN,PLNTOP,F,G,NK)
      DO N=1,NMAX
        KU=2*KMAX+1
        KUX=4*KMAX+1
        IF(ABS(RLAT((N-1)*NR+1)).GE.89.9995) THEN
          SLAT1=SIGN(1.,RLAT((N-1)*NR+1))
          CLAT1=0.
        ELSE
          SLAT1=SIN(PI/180*RLAT((N-1)*NR+1))
          CLAT1=COS(PI/180*RLAT((N-1)*NR+1))
        ENDIF
        CALL SPLEGEND(IROMB,MAXWV,SLAT1,CLAT1,EPS,EPSTOP,
     &                PLN,PLNTOP)
        CALL SPSYNTH(IROMB,MAXWV,2*MAXWV,IDIM,MDIM,2*MXTOP,4*KMAX,
     &               CLAT1,PLN,PLNTOP,MP,W,WTOP,F)
        CALL SPGRADX(MAXWV,IDIM,2*KMAX,MP(2*KMAX+1),CLAT1,
     &               F(1,1,2*KMAX+1),F(1,1,4*KMAX+1))
        CALL SPFFTPT(MAXWV,1,IDIM,1,6*KMAX,RLON((N-1)*NR+1),F,G)
        DO K=1,KMAX
          KD=0*KMAX+K
          KZ=1*KMAX+K
          KU=2*KMAX+K
          KV=3*KMAX+K
          KUX=4*KMAX+K
          KVX=5*KMAX+K
          NK=(N-1)*NG+(K-1)*KG+1
          DP(NK)=G(KD)
          ZP(NK)=G(KZ)
          UP(NK)=G(KU)
          VP(NK)=G(KV)
          UXP(NK)=G(KUX)
          VXP(NK)=G(KVX)
          UYP(NK)=G(KVX)-CLAT1*G(KZ)
          VYP(NK)=CLAT1*G(KD)-G(KUX)
        ENDDO
      ENDDO
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END
