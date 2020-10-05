C> @file
C>
C> Perform a vector spherical transform
C> @author IREDELL @date 96-02-29

C> THIS SUBPROGRAM PERFORMS A SPHERICAL TRANSFORM
C> BETWEEN SPECTRAL COEFFICIENTS OF DIVERGENCES AND CURLS
C> AND VECTOR FIELDS ON A GLOBAL CYLINDRICAL GRID.
C> THE WAVE-SPACE CAN BE EITHER TRIANGULAR OR RHOMBOIDAL.
C> THE GRID-SPACE CAN BE EITHER AN EQUALLY-SPACED GRID
C> (WITH OR WITHOUT POLE POINTS) OR A GAUSSIAN GRID.
C> THE WAVE AND GRID FIELDS MAY HAVE GENERAL INDEXING,
C> BUT EACH WAVE FIELD IS IN SEQUENTIAL 'IBM ORDER',
C> I.E. WITH ZONAL WAVENUMBER AS THE SLOWER INDEX.
C> TRANSFORMS ARE DONE IN LATITUDE PAIRS FOR EFFICIENCY;
C> THUS GRID ARRAYS FOR EACH HEMISPHERE MUST BE PASSED.
C> IF SO REQUESTED, JUST A SUBSET OF THE LATITUDE PAIRS
C> MAY BE TRANSFORMED IN EACH INVOCATION OF THE SUBPROGRAM.
C> THE TRANSFORMS ARE ALL MULTIPROCESSED OVER LATITUDE EXCEPT
C> THE TRANSFORM FROM FOURIER TO SPECTRAL IS MULTIPROCESSED
C> OVER ZONAL WAVENUMBER TO ENSURE REPRODUCIBILITY.
C> TRANSFORM SEVERAL FIELDS AT A TIME TO IMPROVE VECTORIZATION.
C> SUBPROGRAM CAN BE CALLED FROM A MULTIPROCESSING ENVIRONMENT.
C>
C> PROGRAM HISTORY LOG:
C> -  96-02-29  IREDELL
C> - 1998-12-15  IREDELL  GENERIC FFT USED, OPENMP DIRECTIVES INSERTED
C> - 2013-01-16  IREDELL & MIRVIS FIXING AFFT NEGATIVE SHARING EFFECT DURING
C>                       OMP LOOPS BY CREATING TMP AFFT COPY (AFFT_TMP)
C>                       TO BE PRIVATE DURING OMP LOOP THREADING
C>
C> @param IROMB    - INTEGER SPECTRAL DOMAIN SHAPE
C>                (0 FOR TRIANGULAR, 1 FOR RHOMBOIDAL)
C> @param MAXWV    - INTEGER SPECTRAL TRUNCATION
C> @param IDRT     - INTEGER GRID IDENTIFIER
C>                (IDRT=4 FOR GAUSSIAN GRID,
C>                 IDRT=0 FOR EQUALLY-SPACED GRID INCLUDING POLES,
C>                 IDRT=256 FOR EQUALLY-SPACED GRID EXCLUDING POLES)
C> @param IMAX     - INTEGER EVEN NUMBER OF LONGITUDES.
C> @param JMAX     - INTEGER NUMBER OF LATITUDES.
C> @param KMAX     - INTEGER NUMBER OF FIELDS TO TRANSFORM.
C> @param IP       - INTEGER LONGITUDE INDEX FOR THE PRIME MERIDIAN
C> @param IS       - INTEGER SKIP NUMBER BETWEEN LONGITUDES
C> @param JN       - INTEGER SKIP NUMBER BETWEEN N.H. LATITUDES FROM NORTH
C> @param JS       - INTEGER SKIP NUMBER BETWEEN S.H. LATITUDES FROM SOUTH
C> @param KW       - INTEGER SKIP NUMBER BETWEEN WAVE FIELDS
C> @param KG       - INTEGER SKIP NUMBER BETWEEN GRID FIELDS
C> @param JB       - INTEGER LATITUDE INDEX (FROM POLE) TO BEGIN TRANSFORM
C> @param JE       - INTEGER LATITUDE INDEX (FROM POLE) TO END TRANSFORM
C> @param JC       - INTEGER NUMBER OF CPUS OVER WHICH TO MULTIPROCESS
C> @param[out] WAVED    - REAL (*) WAVE DIVERGENCE FIELDS IF IDIR>0
C> [WAVED=(D(GRIDU)/DLAM+D(CLAT*GRIDV)/DPHI)/(CLAT*RERTH)]
C> @param[out] WAVEZ    - REAL (*) WAVE VORTICITY FIELDS IF IDIR>0
C> [WAVEZ=(D(GRIDV)/DLAM-D(CLAT*GRIDU)/DPHI)/(CLAT*RERTH)]      
C> @param[out] GRIDUN   - REAL (*) N.H. GRID U-WINDS (STARTING AT JB) IF IDIR<0
C> @param[out] GRIDUS   - REAL (*) S.H. GRID U-WINDS (STARTING AT JB) IF IDIR<0
C> @param[out] GRIDVN   - REAL (*) N.H. GRID V-WINDS (STARTING AT JB) IF IDIR<0
C> @param[out] GRIDVS   - REAL (*) S.H. GRID V-WINDS (STARTING AT JB) IF IDIR<0
C> @param IDIR     - INTEGER TRANSFORM FLAG
C>                (IDIR>0 FOR WAVE TO GRID, IDIR<0 FOR GRID TO WAVE)
C>
C> SUBPROGRAMS CALLED:
C>  - SPTRANF0     SPTRANF SPECTRAL INITIALIZATION
C>  - SPTRANF1     SPTRANF SPECTRAL TRANSFORM
C>  - SPDZ2UV      COMPUTE WINDS FROM DIVERGENCE AND VORTICITY
C>  - SPUV2DZ      COMPUTE DIVERGENCE AND VORTICITY FROM WINDS
C>
C> REMARKS: MINIMUM GRID DIMENSIONS FOR UNALIASED TRANSFORMS TO SPECTRAL:
C>   DIMENSION                    |LINEAR              |QUADRATIC
C>   -----------------------      |---------           |-------------
C>   IMAX                         |2*MAXWV+2           |3*MAXWV/2*2+2
C>   JMAX (IDRT=4,IROMB=0)        |1*MAXWV+1           |3*MAXWV/2+1
C>   JMAX (IDRT=4,IROMB=1)        |2*MAXWV+1           |5*MAXWV/2+1
C>   JMAX (IDRT=0,IROMB=0)        |2*MAXWV+3           |3*MAXWV/2*2+3
C>   JMAX (IDRT=0,IROMB=1)        |4*MAXWV+3           |5*MAXWV/2*2+3
C>   JMAX (IDRT=256,IROMB=0)      |2*MAXWV+1           |3*MAXWV/2*2+1
C>   JMAX (IDRT=256,IROMB=1)      |4*MAXWV+1           |5*MAXWV/2*2+1
      SUBROUTINE SPTRANFV(IROMB,MAXWV,IDRT,IMAX,JMAX,KMAX,
     &                    IP,IS,JN,JS,KW,KG,JB,JE,JC,
     &                    WAVED,WAVEZ,GRIDUN,GRIDUS,GRIDVN,GRIDVS,IDIR)

      REAL WAVED(*),WAVEZ(*),GRIDUN(*),GRIDUS(*),GRIDVN(*),GRIDVS(*)
      REAL EPS((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EPSTOP(MAXWV+1)
      REAL ENN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL ELONN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL EON((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EONTOP(MAXWV+1)
      REAL(8) AFFT(50000+4*IMAX), AFFT_TMP(50000+4*IMAX)
      REAL CLAT(JB:JE),SLAT(JB:JE),WLAT(JB:JE)
      REAL PLN((MAXWV+1)*((IROMB+1)*MAXWV+2)/2,JB:JE)
      REAL PLNTOP(MAXWV+1,JB:JE)
      INTEGER MP(2)
      REAL W((MAXWV+1)*((IROMB+1)*MAXWV+2)/2*2,2)
      REAL WTOP(2*(MAXWV+1),2)
      REAL G(IMAX,2,2)
      REAL WINC((MAXWV+1)*((IROMB+1)*MAXWV+2)/2*2,2)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  SET PARAMETERS
      MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
      MP=1
      CALL SPTRANF0(IROMB,MAXWV,IDRT,IMAX,JMAX,JB,JE,
     &              EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &              AFFT,CLAT,SLAT,WLAT,PLN,PLNTOP)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM WAVE TO GRID
      IF(IDIR.GT.0) THEN
C$OMP PARALLEL DO PRIVATE(AFFT_TMP,KWS,W,WTOP,G,IJKN,IJKS)
        DO K=1,KMAX
			  AFFT_TMP=AFFT
          KWS=(K-1)*KW
          CALL SPDZ2UV(IROMB,MAXWV,ENN1,ELONN1,EON,EONTOP,
     &                 WAVED(KWS+1),WAVEZ(KWS+1),
     &                 W(1,1),W(1,2),WTOP(1,1),WTOP(1,2))
          DO J=JB,JE
            CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                    EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                    AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                    PLN(1,J),PLNTOP(1,J),MP,
     &                    W(1,1),WTOP(1,1),G(1,1,1),IDIR)
            CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                    EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                    AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                    PLN(1,J),PLNTOP(1,J),MP,
     &                    W(1,2),WTOP(1,2),G(1,1,2),IDIR)
            IF(IP.EQ.1.AND.IS.EQ.1) THEN
              DO I=1,IMAX
                IJKN=I+(J-JB)*JN+(K-1)*KG
                IJKS=I+(J-JB)*JS+(K-1)*KG
                GRIDUN(IJKN)=G(I,1,1)
                GRIDUS(IJKS)=G(I,2,1)
                GRIDVN(IJKN)=G(I,1,2)
                GRIDVS(IJKS)=G(I,2,2)
              ENDDO
            ELSE
              DO I=1,IMAX
                IJKN=MOD(I+IP-2,IMAX)*IS+(J-JB)*JN+(K-1)*KG+1
                IJKS=MOD(I+IP-2,IMAX)*IS+(J-JB)*JS+(K-1)*KG+1
                GRIDUN(IJKN)=G(I,1,1)
                GRIDUS(IJKS)=G(I,2,1)
                GRIDVN(IJKN)=G(I,1,2)
                GRIDVS(IJKS)=G(I,2,2)
              ENDDO
            ENDIF
          ENDDO
        ENDDO
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM GRID TO WAVE
      ELSE
C$OMP PARALLEL DO PRIVATE(AFFT_TMP,KWS,W,WTOP,G,IJKN,IJKS,WINC)
        DO K=1,KMAX
			  AFFT_TMP=AFFT
          KWS=(K-1)*KW
          W=0
          WTOP=0
          DO J=JB,JE
            IF(WLAT(J).GT.0.) THEN
              IF(IP.EQ.1.AND.IS.EQ.1) THEN
                DO I=1,IMAX
                  IJKN=I+(J-JB)*JN+(K-1)*KG
                  IJKS=I+(J-JB)*JS+(K-1)*KG
                  G(I,1,1)=GRIDUN(IJKN)/CLAT(J)**2
                  G(I,2,1)=GRIDUS(IJKS)/CLAT(J)**2
                  G(I,1,2)=GRIDVN(IJKN)/CLAT(J)**2
                  G(I,2,2)=GRIDVS(IJKS)/CLAT(J)**2
                ENDDO
              ELSE
                DO I=1,IMAX
                  IJKN=MOD(I+IP-2,IMAX)*IS+(J-JB)*JN+(K-1)*KG+1
                  IJKS=MOD(I+IP-2,IMAX)*IS+(J-JB)*JS+(K-1)*KG+1
                  G(I,1,1)=GRIDUN(IJKN)/CLAT(J)**2
                  G(I,2,1)=GRIDUS(IJKS)/CLAT(J)**2
                  G(I,1,2)=GRIDVN(IJKN)/CLAT(J)**2
                  G(I,2,2)=GRIDVS(IJKS)/CLAT(J)**2
                ENDDO
              ENDIF
              CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                      EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                      AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                      PLN(1,J),PLNTOP(1,J),MP,
     &                      W(1,1),WTOP(1,1),G(1,1,1),IDIR)
              CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                      EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                      AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                      PLN(1,J),PLNTOP(1,J),MP,
     &                      W(1,2),WTOP(1,2),G(1,1,2),IDIR)
            ENDIF
          ENDDO
          CALL SPUV2DZ(IROMB,MAXWV,ENN1,ELONN1,EON,EONTOP,
     &                 W(1,1),W(1,2),WTOP(1,1),WTOP(1,2),
     &                 WINC(1,1),WINC(1,2))
          WAVED(KWS+1:KWS+2*MX)=WAVED(KWS+1:KWS+2*MX)+WINC(1:2*MX,1)
          WAVEZ(KWS+1:KWS+2*MX)=WAVEZ(KWS+1:KWS+2*MX)+WINC(1:2*MX,2)
        ENDDO
      ENDIF
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END
