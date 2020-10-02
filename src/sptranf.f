C> @file
C>
C> Perform a scalar spherical transform
C> @author IREDELL @date 96-02-29
C>
C> THIS SUBPROGRAM PERFORMS A SPHERICAL TRANSFORM
C>           BETWEEN SPECTRAL COEFFICIENTS OF SCALAR QUANTITIES
C>           AND FIELDS ON A GLOBAL CYLINDRICAL GRID.
C>           THE WAVE-SPACE CAN BE EITHER TRIANGULAR OR RHOMBOIDAL.
C>           THE GRID-SPACE CAN BE EITHER AN EQUALLY-SPACED GRID
C>           (WITH OR WITHOUT POLE POINTS) OR A GAUSSIAN GRID.
C>           THE WAVE AND GRID FIELDS MAY HAVE GENERAL INDEXING,
C>           BUT EACH WAVE FIELD IS IN SEQUENTIAL 'IBM ORDER',
C>           I.E. WITH ZONAL WAVENUMBER AS THE SLOWER INDEX.
C>           TRANSFORMS ARE DONE IN LATITUDE PAIRS FOR EFFICIENCY;
C>           THUS GRID ARRAYS FOR EACH HEMISPHERE MUST BE PASSED.
C>           IF SO REQUESTED, JUST A SUBSET OF THE LATITUDE PAIRS
C>           MAY BE TRANSFORMED IN EACH INVOCATION OF THE SUBPROGRAM.
C>           THE TRANSFORMS ARE ALL MULTIPROCESSED OVER LATITUDE EXCEPT
C>           THE TRANSFORM FROM FOURIER TO SPECTRAL IS MULTIPROCESSED
C>           OVER ZONAL WAVENUMBER TO ENSURE REPRODUCIBILITY.
C>           TRANSFORM SEVERAL FIELDS AT A TIME TO IMPROVE VECTORIZATION.
C>           SUBPROGRAM CAN BE CALLED FROM A MULTIPROCESSING ENVIRONMENT.
C>
C> PROGRAM HISTORY LOG:
C>   96-02-29  IREDELL
C> 1998-12-15  IREDELL  GENERIC FFT USED
C>                      OPENMP DIRECTIVES INSERTED
C> 2013-01-16  IREDELL &    
C>	      MIRVIS    ::	 
C>			FIXING AFFT NEGATIVE SHARING EFFECT DURING
C>			OMP LOOPS BY CREATING TMP AFFT COPY (AFFT_TMP)
C>			TO BE PRIVATE DURING OMP LOOP THREADING	
C>
C> USAGE:    CALL SPTRANF(IROMB,MAXWV,IDRT,IMAX,JMAX,KMAX,
C>    &                   IP,IS,JN,JS,KW,KG,JB,JE,JC,
C>    &                   WAVE,GRIDN,GRIDS,IDIR)
C>   INPUT ARGUMENTS:
C>     IROMB    - INTEGER SPECTRAL DOMAIN SHAPE
C>                (0 FOR TRIANGULAR, 1 FOR RHOMBOIDAL)
C>     MAXWV    - INTEGER SPECTRAL TRUNCATION
C>     IDRT     - INTEGER GRID IDENTIFIER
C>                (IDRT=4 FOR GAUSSIAN GRID,
C>                 IDRT=0 FOR EQUALLY-SPACED GRID INCLUDING POLES,
C>                 IDRT=256 FOR EQUALLY-SPACED GRID EXCLUDING POLES)
C>     IMAX     - INTEGER EVEN NUMBER OF LONGITUDES.
C>     JMAX     - INTEGER NUMBER OF LATITUDES.
C>     KMAX     - INTEGER NUMBER OF FIELDS TO TRANSFORM.
C>     IP       - INTEGER LONGITUDE INDEX FOR THE PRIME MERIDIAN
C>     IS       - INTEGER SKIP NUMBER BETWEEN LONGITUDES
C>     JN       - INTEGER SKIP NUMBER BETWEEN N.H. LATITUDES FROM NORTH
C>     JS       - INTEGER SKIP NUMBER BETWEEN S.H. LATITUDES FROM SOUTH
C>     KW       - INTEGER SKIP NUMBER BETWEEN WAVE FIELDS
C>     KG       - INTEGER SKIP NUMBER BETWEEN GRID FIELDS
C>     JB       - INTEGER LATITUDE INDEX (FROM POLE) TO BEGIN TRANSFORM
C>     JE       - INTEGER LATITUDE INDEX (FROM POLE) TO END TRANSFORM
C>     JC       - INTEGER NUMBER OF CPUS OVER WHICH TO MULTIPROCESS
C>     WAVE     - REAL (*) WAVE FIELDS IF IDIR>0
C>     GRIDN    - REAL (*) N.H. GRID FIELDS (STARTING AT JB) IF IDIR<0
C>     GRIDS    - REAL (*) S.H. GRID FIELDS (STARTING AT JB) IF IDIR<0
C>     IDIR     - INTEGER TRANSFORM FLAG
C>                (IDIR>0 FOR WAVE TO GRID, IDIR<0 FOR GRID TO WAVE)
C>   OUTPUT ARGUMENTS:
C>     WAVE     - REAL (*) WAVE FIELDS IF IDIR<0
C>     GRIDN    - REAL (*) N.H. GRID FIELDS (STARTING AT JB) IF IDIR>0
C>     GRIDS    - REAL (*) S.H. GRID FIELDS (STARTING AT JB) IF IDIR>0
C>
C> SUBPROGRAMS CALLED:
C>   SPTRANF0     SPTRANF SPECTRAL INITIALIZATION
C>   SPTRANF1     SPTRANF SPECTRAL TRANSFORM
C>
C> REMARKS: MINIMUM GRID DIMENSIONS FOR UNALIASED TRANSFORMS TO SPECTRAL:
C>   DIMENSION                    LINEAR              QUADRATIC
C>   -----------------------      ---------           -------------
C>   IMAX                         2*MAXWV+2           3*MAXWV/2*2+2
C>   JMAX (IDRT=4,IROMB=0)        1*MAXWV+1           3*MAXWV/2+1
C>   JMAX (IDRT=4,IROMB=1)        2*MAXWV+1           5*MAXWV/2+1
C>   JMAX (IDRT=0,IROMB=0)        2*MAXWV+3           3*MAXWV/2*2+3
C>   JMAX (IDRT=0,IROMB=1)        4*MAXWV+3           5*MAXWV/2*2+3
C>   JMAX (IDRT=256,IROMB=0)      2*MAXWV+1           3*MAXWV/2*2+1
C>   JMAX (IDRT=256,IROMB=1)      4*MAXWV+1           5*MAXWV/2*2+1
C>   -----------------------      ---------           -------------
C>
C>
C-----------------------------------------------------------------------
      SUBROUTINE SPTRANF(IROMB,MAXWV,IDRT,IMAX,JMAX,KMAX,
     &                   IP,IS,JN,JS,KW,KG,JB,JE,JC,
     &                   WAVE,GRIDN,GRIDS,IDIR)

      REAL WAVE(*),GRIDN(*),GRIDS(*)
      REAL EPS((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EPSTOP(MAXWV+1)
      REAL ENN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL ELONN1((MAXWV+1)*((IROMB+1)*MAXWV+2)/2)
      REAL EON((MAXWV+1)*((IROMB+1)*MAXWV+2)/2),EONTOP(MAXWV+1)
      REAL(8) AFFT(50000+4*IMAX), AFFT_TMP(50000+4*IMAX)
      REAL CLAT(JB:JE),SLAT(JB:JE),WLAT(JB:JE)
      REAL PLN((MAXWV+1)*((IROMB+1)*MAXWV+2)/2,JB:JE)
      REAL PLNTOP(MAXWV+1,JB:JE)
      REAL WTOP(2*(MAXWV+1))
      REAL G(IMAX,2)
!      write(0,*) 'sptranf top'
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  SET PARAMETERS
      MP=0
      CALL SPTRANF0(IROMB,MAXWV,IDRT,IMAX,JMAX,JB,JE,
     &              EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &              AFFT,CLAT,SLAT,WLAT,PLN,PLNTOP)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM WAVE TO GRID
      IF(IDIR.GT.0) THEN
C$OMP PARALLEL DO PRIVATE(AFFT_TMP,KWS,WTOP,G,IJKN,IJKS)
        DO K=1,KMAX
			  AFFT_TMP=AFFT
          KWS=(K-1)*KW
          WTOP=0
          DO J=JB,JE
            CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                    EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                    AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                    PLN(1,J),PLNTOP(1,J),MP,
     &                    WAVE(KWS+1),WTOP,G,IDIR)
            IF(IP.EQ.1.AND.IS.EQ.1) THEN
              DO I=1,IMAX
                IJKN=I+(J-JB)*JN+(K-1)*KG
                IJKS=I+(J-JB)*JS+(K-1)*KG
                GRIDN(IJKN)=G(I,1)
                GRIDS(IJKS)=G(I,2)
              ENDDO
            ELSE
              DO I=1,IMAX
                IJKN=MOD(I+IP-2,IMAX)*IS+(J-JB)*JN+(K-1)*KG+1
                IJKS=MOD(I+IP-2,IMAX)*IS+(J-JB)*JS+(K-1)*KG+1
                GRIDN(IJKN)=G(I,1)
                GRIDS(IJKS)=G(I,2)
              ENDDO
            ENDIF
          ENDDO
        ENDDO
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM GRID TO WAVE
      ELSE
C$OMP PARALLEL DO PRIVATE(AFFT_TMP,KWS,WTOP,G,IJKN,IJKS)
        DO K=1,KMAX
			  AFFT_TMP=AFFT
          KWS=(K-1)*KW
          WTOP=0
          DO J=JB,JE
            IF(WLAT(J).GT.0.) THEN
              IF(IP.EQ.1.AND.IS.EQ.1) THEN
                DO I=1,IMAX
                  IJKN=I+(J-JB)*JN+(K-1)*KG
                  IJKS=I+(J-JB)*JS+(K-1)*KG
                  G(I,1)=GRIDN(IJKN)
                  G(I,2)=GRIDS(IJKS)
                ENDDO
              ELSE
                DO I=1,IMAX
                  IJKN=MOD(I+IP-2,IMAX)*IS+(J-JB)*JN+(K-1)*KG+1
                  IJKS=MOD(I+IP-2,IMAX)*IS+(J-JB)*JS+(K-1)*KG+1
                  G(I,1)=GRIDN(IJKN)
                  G(I,2)=GRIDS(IJKS)
                ENDDO
              ENDIF
              CALL SPTRANF1(IROMB,MAXWV,IDRT,IMAX,JMAX,J,J,
     &                      EPS,EPSTOP,ENN1,ELONN1,EON,EONTOP,
     &                      AFFT_TMP,CLAT(J),SLAT(J),WLAT(J),
     &                      PLN(1,J),PLNTOP(1,J),MP,
     &                      WAVE(KWS+1),WTOP,G,IDIR)
            ENDIF
          ENDDO
        ENDDO
      ENDIF
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END
