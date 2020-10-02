C> @file
C>
C> Compute x-gradient in fourier space
C> @author IREDELL @date 96-02-20
C>
C> THIS SUBPROGRAM COMPUTES THE X-GRADIENT OF FIELDS
C>           IN COMPLEX FOURIER SPACE.
C>           THE X-GRADIENT OF A VECTOR FIELD W IS
C>             WX=CONJG(W)*L/RERTH
C>           WHERE L IS THE WAVENUMBER AND RERTH IS THE EARTH RADIUS,
C>           SO THAT THE RESULT IS THE X-GRADIENT OF THE PSEUDO-VECTOR.
C>           THE X-GRADIENT OF A SCALAR FIELD W IS
C>             WX=CONJG(W)*L/(RERTH*CLAT)
C>           WHERE CLAT IS THE COSINE OF LATITUDE.
C>           AT THE POLE THIS IS UNDEFINED, SO THE WAY TO GET
C>           THE X-GRADIENT AT THE POLE IS BY PASSING BOTH
C>           THE WEIGHTED WAVENUMBER 0 AND THE UNWEIGHTED WAVENUMBER 1 
C>           AMPLITUDES AT THE POLE AND SETTING MP=10.
C>           IN THIS CASE, THE WAVENUMBER 1 AMPLITUDES ARE USED
C>           TO COMPUTE THE X-GRADIENT AND THEN ZEROED OUT.
C>
C> PROGRAM HISTORY LOG:
C> 1998-12-18  IREDELL
C>
C> USAGE:    CALL SPGRADX(M,INCW,KMAX,W,WX)
C>
C>   INPUT ARGUMENT LIST:
C>     M        - INTEGER FOURIER WAVENUMBER TRUNCATION
C>     INCW     - INTEGER FIRST DIMENSION OF THE COMPLEX AMPLITUDE ARRAY
C>                (INCW >= M+1)
C>     KMAX     - INTEGER NUMBER OF FOURIER FIELDS
C>     MP       - INTEGER (KM) IDENTIFIERS
C>                (0 OR 10 FOR SCALAR, 1 FOR VECTOR)
C>     CLAT     - REAL COSINE OF LATITUDE
C>     W        - COMPLEX(INCW,KMAX) FOURIER AMPLITUDES
C>
C>   OUTPUT ARGUMENT LIST:
C>     W        - COMPLEX(INCW,KMAX) FOURIER AMPLITUDES
C>                CORRECTED WHEN MP=10 AND CLAT=0
C>     WX       - COMPLEX(INCW,KMAX) COMPLEX AMPLITUDES OF X-GRADIENTS
C>
C> SUBPROGRAMS CALLED:
C>
C>
C> REMARKS:
C>   THIS SUBPROGRAM IS THREAD-SAFE.
C>
C-----------------------------------------------------------------------
      SUBROUTINE SPGRADX(M,INCW,KMAX,MP,CLAT,W,WX)

        IMPLICIT NONE
        INTEGER,INTENT(IN):: M,INCW,KMAX,MP(KMAX)
        REAL,INTENT(IN):: CLAT
        REAL,INTENT(INOUT):: W(2*INCW,KMAX)
        REAL,INTENT(OUT):: WX(2*INCW,KMAX)
        INTEGER K,L
        REAL,PARAMETER:: RERTH=6.3712E6
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        DO K=1,KMAX
          IF(MP(K).EQ.1) THEN
            DO L=0,M
              WX(2*L+1,K)=-W(2*L+2,K)*(L/RERTH)
              WX(2*L+2,K)=+W(2*L+1,K)*(L/RERTH)
            ENDDO
          ELSEIF(CLAT.EQ.0.) THEN
            DO L=0,M
              WX(2*L+1,K)=0
              WX(2*L+2,K)=0
            ENDDO
            IF(MP(K).EQ.10.AND.M.GE.2) THEN
              WX(3,K)=-W(4,K)/RERTH
              WX(4,K)=+W(3,K)/RERTH
              W(3,K)=0
              W(4,K)=0
            ENDIF
          ELSE
            DO L=0,M
              WX(2*L+1,K)=-W(2*L+2,K)*(L/(RERTH*CLAT))
              WX(2*L+2,K)=+W(2*L+1,K)*(L/(RERTH*CLAT))
            ENDDO
          ENDIF
        ENDDO
C - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      END SUBROUTINE
