C> @file
C>
C> Spectrally truncate to gradients
C> @author IREDELL @date 96-02-29
C>
C> THIS SUBPROGRAM SPECTRALLY TRUNCATES SCALAR FIELDS
C>           ON A GLOBAL CYLINDRICAL GRID, RETURNING THEIR MEANS AND
C>           GRADIENTS TO A POSSIBLY DIFFERENT GLOBAL CYLINDRICAL GRID.
C>           THE WAVE-SPACE CAN BE EITHER TRIANGULAR OR RHOMBOIDAL.
C>           EITHER GRID-SPACE CAN BE EITHER AN EQUALLY-SPACED GRID
C>           (WITH OR WITHOUT POLE POINTS) OR A GAUSSIAN GRID.
C>           THE GRID FIELDS MAY HAVE GENERAL INDEXING.
C>           THE TRANSFORMS ARE ALL MULTIPROCESSED.
C>           OVER ZONAL WAVENUMBER TO ENSURE REPRODUCIBILITY.
C>           TRANSFORM SEVERAL FIELDS AT A TIME TO IMPROVE VECTORIZATION.
C>           SUBPROGRAM CAN BE CALLED FROM A MULTIPROCESSING ENVIRONMENT.
C>
C> PROGRAM HISTORY LOG:
C>   96-02-29  IREDELL
C>
C> USAGE:    CALL SPTRUND(IROMB,MAXWV,IDRTI,IMAXI,JMAXI,
C>    &                   IDRTO,IMAXO,JMAXO,KMAX,
C>    &                   IPRIME,ISKIPI,JSKIPI,KSKIPI,
C>    &                   ISKIPO,JSKIPO,KSKIPO,JCPU,GRID,
C>    &                   GRIDMN,GRIDX,GRIDY)
C>   INPUT ARGUMENTS:
C>     IROMB    - INTEGER SPECTRAL DOMAIN SHAPE
C>                (0 FOR TRIANGULAR, 1 FOR RHOMBOIDAL)
C>     MAXWV    - INTEGER SPECTRAL TRUNCATION
C>     IDRTI    - INTEGER INPUT GRID IDENTIFIER
C>                (IDRTI=4 FOR GAUSSIAN GRID,
C>                 IDRTI=0 FOR EQUALLY-SPACED GRID INCLUDING POLES,
C>                 IDRTI=256 FOR EQUALLY-SPACED GRID EXCLUDING POLES)
C>     IMAXI    - INTEGER EVEN NUMBER OF INPUT LONGITUDES.
C>     JMAXI    - INTEGER NUMBER OF INPUT LATITUDES.
C>     IDRTO    - INTEGER OUTPUT GRID IDENTIFIER
C>                (IDRTO=4 FOR GAUSSIAN GRID,
C>                 IDRTO=0 FOR EQUALLY-SPACED GRID INCLUDING POLES,
C>                 IDRTO=256 FOR EQUALLY-SPACED GRID EXCLUDING POLES)
C>     IMAXO    - INTEGER EVEN NUMBER OF OUTPUT LONGITUDES.
C>     JMAXO    - INTEGER NUMBER OF OUTPUT LATITUDES.
C>     KMAX     - INTEGER NUMBER OF FIELDS TO TRANSFORM.
C>     IPRIME   - INTEGER INPUT LONGITUDE INDEX FOR THE PRIME MERIDIAN.
C>                (DEFAULTS TO 1 IF IPRIME=0)
C>                (OUTPUT LONGITUDE INDEX FOR PRIME MERIDIAN ASSUMED 1.)
C>     ISKIPI   - INTEGER SKIP NUMBER BETWEEN INPUT LONGITUDES
C>                (DEFAULTS TO 1 IF ISKIPI=0)
C>     JSKIPI   - INTEGER SKIP NUMBER BETWEEN INPUT LATITUDES FROM SOUTH
C>                (DEFAULTS TO -IMAXI IF JSKIPI=0)
C>     KSKIPI   - INTEGER SKIP NUMBER BETWEEN INPUT GRID FIELDS
C>                (DEFAULTS TO IMAXI*JMAXI IF KSKIPI=0)
C>     ISKIPO   - INTEGER SKIP NUMBER BETWEEN OUTPUT LONGITUDES
C>                (DEFAULTS TO 1 IF ISKIPO=0)
C>     JSKIPO   - INTEGER SKIP NUMBER BETWEEN OUTPUT LATITUDES FROM SOUTH
C>                (DEFAULTS TO -IMAXO IF JSKIPO=0)
C>     KSKIPO   - INTEGER SKIP NUMBER BETWEEN OUTPUT GRID FIELDS
C>                (DEFAULTS TO IMAXO*JMAXO IF KSKIPO=0)
C>     JCPU     - INTEGER NUMBER OF CPUS OVER WHICH TO MULTIPROCESS
C>                (DEFAULTS TO ENVIRONMENT NCPUS IF JCPU=0)
C>     GRID     - REAL (*) INPUT GRID FIELDS
C>   OUTPUT ARGUMENTS:
C>     GRIDMN   - REAL (KMAX) OUTPUT GLOBAL MEANS
C>     GRIDX    - REAL (*) OUTPUT X-GRADIENTS
C>     GRIDY    - REAL (*) OUTPUT Y-GRADIENTS
C>
C> SUBPROGRAMS CALLED:
C>   SPTRAN       PERFORM A SCALAR SPHERICAL TRANSFORM
C>   SPTRAND      PERFORM A GRADIENT SPHERICAL TRANSFORM
C>   NCPUS        GETS ENVIRONMENT NUMBER OF CPUS
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
      SUBROUTINE SPTRUND(IROMB,MAXWV,IDRTI,IMAXI,JMAXI,
     &                   IDRTO,IMAXO,JMAXO,KMAX,
     &                   IPRIME,ISKIPI,JSKIPI,KSKIPI,
     &                   ISKIPO,JSKIPO,KSKIPO,JCPU,GRID,
     &                   GRIDMN,GRIDX,GRIDY)

      REAL GRID(*),GRIDX(*),GRIDY(*)
      REAL W((MAXWV+1)*((IROMB+1)*MAXWV+2)/2*2+1,KMAX)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM INPUT GRID TO WAVE
      JC=JCPU
      IF(JC.EQ.0) JC=NCPUS()
      MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
      MDIM=2*MX+1
      JN=-JSKIPI
      IF(JN.EQ.0) JN=IMAXI
      JS=-JN
      INP=(JMAXI-1)*MAX(0,-JN)+1
      ISP=(JMAXI-1)*MAX(0,-JS)+1
      CALL SPTRAN(IROMB,MAXWV,IDRTI,IMAXI,JMAXI,KMAX,
     &            IPRIME,ISKIPI,JN,JS,MDIM,KSKIPI,0,0,JC,
     &            W,GRID(INP),GRID(ISP),-1)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
C  TRANSFORM WAVE TO OUTPUT GRADIENTS
      JN=-JSKIPO
      IF(JN.EQ.0) JN=IMAXO
      JS=-JN
      INP=(JMAXO-1)*MAX(0,-JN)+1
      ISP=(JMAXO-1)*MAX(0,-JS)+1
      CALL SPTRAND(IROMB,MAXWV,IDRTO,IMAXO,JMAXO,KMAX,
     &             0,ISKIPO,JN,JS,MDIM,KSKIPO,0,0,JC,
     &             W,GRIDMN,
     &             GRIDX(INP),GRIDX(ISP),GRIDY(INP),GRIDY(ISP),1)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END
