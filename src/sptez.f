C> @file
C>
C> Perform a simple scalar spherical transform
C> @author IREDELL @date 96-02-29
C>
C> THIS SUBPROGRAM PERFORMS A SPHERICAL TRANSFORM
C>           BETWEEN SPECTRAL COEFFICIENTS OF A SCALAR QUANTITY
C>           AND A FIELD ON A GLOBAL CYLINDRICAL GRID.
C>           THE WAVE-SPACE CAN BE EITHER TRIANGULAR OR RHOMBOIDAL.
C>           THE GRID-SPACE CAN BE EITHER AN EQUALLY-SPACED GRID
C>           (WITH OR WITHOUT POLE POINTS) OR A GAUSSIAN GRID.
C>           THE WAVE FIELD IS IN SEQUENTIAL 'IBM ORDER'.
C>           THE GRID FIELD IS INDEXED EAST TO WEST, THEN NORTH TO SOUTH.
C>           FOR MORE FLEXIBILITY AND EFFICIENCY, CALL SPTRAN.
C>           SUBPROGRAM CAN BE CALLED FROM A MULTIPROCESSING ENVIRONMENT.
C>
C> PROGRAM HISTORY LOG:
C>   96-02-29  IREDELL
C>
C> USAGE:    CALL SPTEZ(IROMB,MAXWV,IDRT,IMAX,JMAX,WAVE,GRID,IDIR)
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
C>     WAVE     - REAL (2*MX) WAVE FIELD IF IDIR>0
C>                WHERE MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
C>     GRID     - REAL (IMAX,JMAX) GRID FIELD (E->W,N->S) IF IDIR<0
C>     IDIR     - INTEGER TRANSFORM FLAG
C>                (IDIR>0 FOR WAVE TO GRID, IDIR<0 FOR GRID TO WAVE)
C>   OUTPUT ARGUMENTS:
C>     WAVE     - REAL (2*MX) WAVE FIELD IF IDIR<0
C>                WHERE MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
C>     GRID     - REAL (IMAX,JMAX) GRID FIELD (E->W,N->S) IF IDIR>0
C>
C> SUBPROGRAMS CALLED:
C>   SPTRANF      PERFORM A SCALAR SPHERICAL TRANSFORM
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
      SUBROUTINE SPTEZ(IROMB,MAXWV,IDRT,IMAX,JMAX,WAVE,GRID,IDIR)

      REAL WAVE((MAXWV+1)*((IROMB+1)*MAXWV+2))
      REAL GRID(IMAX,JMAX)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      MX=(MAXWV+1)*((IROMB+1)*MAXWV+2)/2
      IP=1
      IS=1
      JN=IMAX
      JS=-JN
      KW=2*MX
      KG=IMAX*JMAX
      JB=1
      JE=(JMAX+1)/2
      JC=NCPUS()
!	print *, " EM: SPTEZ:::JJJJJJJJJJJJJJJJJJJCCCCCCCCCCC=" ,JC	
      IF(IDIR.LT.0) WAVE=0
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      CALL SPTRANF(IROMB,MAXWV,IDRT,IMAX,JMAX,1,
     &             IP,IS,JN,JS,KW,KG,JB,JE,JC,
     &             WAVE,GRID,GRID(1,JMAX),IDIR)
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END
