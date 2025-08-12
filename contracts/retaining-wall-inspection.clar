;; Retaining Wall Inspection Contract
;; Conducts safety inspections of walls supporting roads and buildings

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-WALL-NOT-FOUND (err u101))
(define-constant ERR-INVALID-RATING (err u102))
(define-constant ERR-INSPECTOR-NOT-CERTIFIED (err u103))
(define-constant ERR-INSPECTION-TOO-RECENT (err u104))

;; Data Variables
(define-data-var next-wall-id uint u1)
(define-data-var next-inspection-id uint u1)
(define-data-var min-inspection-interval uint u2160) ;; ~15 days in blocks

;; Data Maps
(define-map retaining-walls
  { wall-id: uint }
  {
    location: (string-ascii 100),
    construction-date: uint,
    height: uint,
    length: uint,
    material-type: (string-ascii 50),
    load-capacity: uint,
    current-rating: uint,
    last-inspection: uint,
    owner: principal
  }
)

(define-map certified-inspectors
  { inspector: principal }
  {
    certification-date: uint,
    certification-level: uint,
    active: bool,
    inspections-completed: uint
  }
)

(define-map inspection-records
  { inspection-id: uint }
  {
    wall-id: uint,
    inspector: principal,
    inspection-date: uint,
    safety-rating: uint,
    structural-integrity: uint,
    drainage-condition: uint,
    erosion-signs: uint,
    recommended-actions: (string-ascii 200),
    urgent-repair-needed: bool,
    next-inspection-due: uint
  }
)

(define-map wall-inspection-history
  { wall-id: uint, inspection-date: uint }
  { inspection-id: uint }
)

;; Public Functions

;; Register a new retaining wall
(define-public (register-wall
  (location (string-ascii 100))
  (construction-date uint)
  (height uint)
  (length uint)
  (material-type (string-ascii 50))
  (load-capacity uint))
  (let ((wall-id (var-get next-wall-id)))
    (asserts! (> height u0) ERR-INVALID-RATING)
    (asserts! (> length u0) ERR-INVALID-RATING)
    (asserts! (> load-capacity u0) ERR-INVALID-RATING)

    (map-set retaining-walls
      { wall-id: wall-id }
      {
        location: location,
        construction-date: construction-date,
        height: height,
        length: length,
        material-type: material-type,
        load-capacity: load-capacity,
        current-rating: u10,
        last-inspection: u0,
        owner: tx-sender
      }
    )

    (var-set next-wall-id (+ wall-id u1))
    (ok wall-id)
  )
)

;; Certify an inspector
(define-public (certify-inspector
  (inspector principal)
  (certification-level uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= certification-level u1) (<= certification-level u5)) ERR-INVALID-RATING)

    (map-set certified-inspectors
      { inspector: inspector }
      {
        certification-date: block-height,
        certification-level: certification-level,
        active: true,
        inspections-completed: u0
      }
    )
    (ok true)
  )
)

;; Conduct inspection
(define-public (conduct-inspection
  (wall-id uint)
  (safety-rating uint)
  (structural-integrity uint)
  (drainage-condition uint)
  (erosion-signs uint)
  (recommended-actions (string-ascii 200))
  (urgent-repair-needed bool))
  (let (
    (inspection-id (var-get next-inspection-id))
    (wall-data (unwrap! (map-get? retaining-walls { wall-id: wall-id }) ERR-WALL-NOT-FOUND))
    (inspector-data (unwrap! (map-get? certified-inspectors { inspector: tx-sender }) ERR-INSPECTOR-NOT-CERTIFIED))
    (last-inspection (get last-inspection wall-data))
  )
    (asserts! (get active inspector-data) ERR-INSPECTOR-NOT-CERTIFIED)
    (asserts! (and (>= safety-rating u1) (<= safety-rating u10)) ERR-INVALID-RATING)
    (asserts! (and (>= structural-integrity u1) (<= structural-integrity u10)) ERR-INVALID-RATING)
    (asserts! (and (>= drainage-condition u1) (<= drainage-condition u10)) ERR-INVALID-RATING)
    (asserts! (and (>= erosion-signs u1) (<= erosion-signs u10)) ERR-INVALID-RATING)
    (asserts! (or (is-eq last-inspection u0)
                  (>= (- block-height last-inspection) (var-get min-inspection-interval)))
              ERR-INSPECTION-TOO-RECENT)

    ;; Record inspection
    (map-set inspection-records
      { inspection-id: inspection-id }
      {
        wall-id: wall-id,
        inspector: tx-sender,
        inspection-date: block-height,
        safety-rating: safety-rating,
        structural-integrity: structural-integrity,
        drainage-condition: drainage-condition,
        erosion-signs: erosion-signs,
        recommended-actions: recommended-actions,
        urgent-repair-needed: urgent-repair-needed,
        next-inspection-due: (+ block-height u4320) ;; ~30 days
      }
    )

    ;; Update wall data
    (map-set retaining-walls
      { wall-id: wall-id }
      (merge wall-data {
        current-rating: safety-rating,
        last-inspection: block-height
      })
    )

    ;; Update inspection history
    (map-set wall-inspection-history
      { wall-id: wall-id, inspection-date: block-height }
      { inspection-id: inspection-id }
    )

    ;; Update inspector stats
    (map-set certified-inspectors
      { inspector: tx-sender }
      (merge inspector-data {
        inspections-completed: (+ (get inspections-completed inspector-data) u1)
      })
    )

    (var-set next-inspection-id (+ inspection-id u1))
    (ok inspection-id)
  )
)

;; Read-only functions

(define-read-only (get-wall-info (wall-id uint))
  (map-get? retaining-walls { wall-id: wall-id })
)

(define-read-only (get-inspection-record (inspection-id uint))
  (map-get? inspection-records { inspection-id: inspection-id })
)

(define-read-only (get-inspector-info (inspector principal))
  (map-get? certified-inspectors { inspector: inspector })
)

(define-read-only (is-inspection-due (wall-id uint))
  (match (map-get? retaining-walls { wall-id: wall-id })
    wall-data
      (let ((last-inspection (get last-inspection wall-data)))
        (if (is-eq last-inspection u0)
          true
          (>= (- block-height last-inspection) (var-get min-inspection-interval))
        )
      )
    false
  )
)

(define-read-only (get-walls-needing-inspection)
  (ok "Use off-chain indexing to query walls needing inspection")
)
