;; Candidate Registration Contract
;; Manages political candidate eligibility and campaign finance

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-ALREADY-REGISTERED (err u301))
(define-constant ERR-INVALID-CANDIDATE (err u302))
(define-constant ERR-REGISTRATION-CLOSED (err u303))
(define-constant ERR-INSUFFICIENT-ENDORSEMENTS (err u304))
(define-constant ERR-SPENDING-LIMIT-EXCEEDED (err u305))
(define-constant ERR-CANDIDATE-NOT-FOUND (err u306))

;; Data Variables
(define-data-var registration-open bool true)
(define-data-var minimum-endorsements uint u10)
(define-data-var campaign-spending-limit uint u1000000) ;; In microSTX
(define-data-var total-candidates uint u0)

;; Data Maps
(define-map candidates
  { candidate-id: (buff 32) }
  {
    name: (string-ascii 100),
    party: (string-ascii 50),
    platform: (string-ascii 500),
    endorsements: uint,
    registration-block: uint,
    is-qualified: bool,
    total-spending: uint,
    wallet-address: principal
  }
)

(define-map endorsements
  { candidate-id: (buff 32), endorser: principal }
  { endorsed-at: uint, endorsement-type: (string-ascii 20) }
)

(define-map campaign-expenses
  { candidate-id: (buff 32), expense-id: uint }
  {
    amount: uint,
    description: (string-ascii 200),
    category: (string-ascii 50),
    reported-at: uint,
    verified: bool
  }
)

(define-map candidate-qualifications
  { candidate-id: (buff 32) }
  {
    age-verified: bool,
    citizenship-verified: bool,
    criminal-background-clear: bool,
    education-verified: bool,
    qualification-score: uint
  }
)

;; Public Functions

;; Register a new candidate
(define-public (register-candidate
  (candidate-id (buff 32))
  (name (string-ascii 100))
  (party (string-ascii 50))
  (platform (string-ascii 500))
  (wallet-address principal))
  (begin
    (asserts! (var-get registration-open) ERR-REGISTRATION-CLOSED)
    (asserts! (is-none (map-get? candidates { candidate-id: candidate-id })) ERR-ALREADY-REGISTERED)
    (asserts! (> (len name) u0) ERR-INVALID-CANDIDATE)

    (map-set candidates
      { candidate-id: candidate-id }
      {
        name: name,
        party: party,
        platform: platform,
        endorsements: u0,
        registration-block: block-height,
        is-qualified: false,
        total-spending: u0,
        wallet-address: wallet-address
      }
    )

    (map-set candidate-qualifications
      { candidate-id: candidate-id }
      {
        age-verified: false,
        citizenship-verified: false,
        criminal-background-clear: false,
        education-verified: false,
        qualification-score: u0
      }
    )

    (var-set total-candidates (+ (var-get total-candidates) u1))
    (ok candidate-id)
  )
)

;; Endorse a candidate
(define-public (endorse-candidate (candidate-id (buff 32)) (endorsement-type (string-ascii 20)))
  (let (
    (candidate-data (unwrap! (map-get? candidates { candidate-id: candidate-id }) ERR-CANDIDATE-NOT-FOUND))
  )
    (asserts! (is-none (map-get? endorsements { candidate-id: candidate-id, endorser: tx-sender })) ERR-ALREADY-REGISTERED)

    (map-set endorsements
      { candidate-id: candidate-id, endorser: tx-sender }
      { endorsed-at: block-height, endorsement-type: endorsement-type }
    )

    (let ((new-endorsement-count (+ (get endorsements candidate-data) u1)))
      (map-set candidates
        { candidate-id: candidate-id }
        (merge candidate-data {
          endorsements: new-endorsement-count,
          is-qualified: (>= new-endorsement-count (var-get minimum-endorsements))
        })
      )
      (ok new-endorsement-count)
    )
  )
)

;; Report campaign expense
(define-public (report-campaign-expense
  (candidate-id (buff 32))
  (expense-id uint)
  (amount uint)
  (description (string-ascii 200))
  (category (string-ascii 50)))
  (let (
    (candidate-data (unwrap! (map-get? candidates { candidate-id: candidate-id }) ERR-CANDIDATE-NOT-FOUND))
    (new-total-spending (+ (get total-spending candidate-data) amount))
  )
    (asserts! (is-eq tx-sender (get wallet-address candidate-data)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-total-spending (var-get campaign-spending-limit)) ERR-SPENDING-LIMIT-EXCEEDED)

    (map-set campaign-expenses
      { candidate-id: candidate-id, expense-id: expense-id }
      {
        amount: amount,
        description: description,
        category: category,
        reported-at: block-height,
        verified: false
      }
    )

    (map-set candidates
      { candidate-id: candidate-id }
      (merge candidate-data { total-spending: new-total-spending })
    )

    (ok new-total-spending)
  )
)

;; Verify candidate qualification
(define-public (verify-candidate-qualification
  (candidate-id (buff 32))
  (qualification-type (string-ascii 20))
  (verified bool))
  (let (
    (qual-data (unwrap! (map-get? candidate-qualifications { candidate-id: candidate-id }) ERR-CANDIDATE-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (let (
      (updated-quals (if (is-eq qualification-type "age")
                        (merge qual-data { age-verified: verified })
                        (if (is-eq qualification-type "citizenship")
                          (merge qual-data { citizenship-verified: verified })
                          (if (is-eq qualification-type "criminal")
                            (merge qual-data { criminal-background-clear: verified })
                            (if (is-eq qualification-type "education")
                              (merge qual-data { education-verified: verified })
                              qual-data)))))
    )
      (map-set candidate-qualifications
        { candidate-id: candidate-id }
        (merge updated-quals {
          qualification-score: (+
            (if (get age-verified updated-quals) u1 u0)
            (if (get citizenship-verified updated-quals) u1 u0)
            (if (get criminal-background-clear updated-quals) u1 u0)
            (if (get education-verified updated-quals) u1 u0))
        })
      )
      (ok true)
    )
  )
)

;; Verify campaign expense
(define-public (verify-campaign-expense (candidate-id (buff 32)) (expense-id uint))
  (let (
    (expense-data (unwrap! (map-get? campaign-expenses { candidate-id: candidate-id, expense-id: expense-id }) ERR-CANDIDATE-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set campaign-expenses
      { candidate-id: candidate-id, expense-id: expense-id }
      (merge expense-data { verified: true })
    )
    (ok true)
  )
)

;; Administrative Functions

(define-public (toggle-registration)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set registration-open (not (var-get registration-open)))
    (ok (var-get registration-open))
  )
)

(define-public (set-minimum-endorsements (minimum uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set minimum-endorsements minimum)
    (ok minimum)
  )
)

(define-public (set-spending-limit (limit uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set campaign-spending-limit limit)
    (ok limit)
  )
)

;; Read-only Functions

(define-read-only (get-candidate-info (candidate-id (buff 32)))
  (map-get? candidates { candidate-id: candidate-id })
)

(define-read-only (get-candidate-qualifications (candidate-id (buff 32)))
  (map-get? candidate-qualifications { candidate-id: candidate-id })
)

(define-read-only (get-campaign-expense (candidate-id (buff 32)) (expense-id uint))
  (map-get? campaign-expenses { candidate-id: candidate-id, expense-id: expense-id })
)

(define-read-only (is-candidate-qualified (candidate-id (buff 32)))
  (match (map-get? candidates { candidate-id: candidate-id })
    candidate-data (get is-qualified candidate-data)
    false
  )
)

(define-read-only (get-endorsement-info (candidate-id (buff 32)) (endorser principal))
  (map-get? endorsements { candidate-id: candidate-id, endorser: endorser })
)

(define-read-only (get-total-candidates)
  (var-get total-candidates)
)

(define-read-only (is-registration-open)
  (var-get registration-open)
)

(define-read-only (get-spending-limit)
  (var-get campaign-spending-limit)
)
