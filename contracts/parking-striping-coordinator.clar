;; Parking Striping Coordinator Smart Contract
;; Manages commercial property parking lot maintenance and compliance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-project-complete (err u104))
(define-constant err-not-assigned (err u105))
(define-constant err-already-exists (err u106))

;; Data Variables
(define-data-var property-id-nonce uint u0)
(define-data-var project-id-nonce uint u0)
(define-data-var assessment-id-nonce uint u0)
(define-data-var total-properties uint u0)
(define-data-var total-projects uint u0)
(define-data-var total-budget-allocated uint u0)

;; Data Maps
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    location: (string-ascii 256),
    lot-size: uint,
    parking-capacity: uint,
    last-striping-date: uint,
    next-scheduled-date: (optional uint),
    ada-compliant: bool,
    condition-score: uint
  }
)

(define-map condition-assessments
  { assessment-id: uint }
  {
    property-id: uint,
    assessment-date: uint,
    assessor: principal,
    visibility-score: uint,
    wear-rating: uint,
    deficiencies: (string-ascii 512),
    recommended-action: (string-ascii 256),
    urgency-level: uint
  }
)

(define-map restriping-projects
  { project-id: uint }
  {
    property-id: uint,
    scope-description: (string-ascii 512),
    budget-allocated: uint,
    created-date: uint,
    scheduled-start: uint,
    contractor-assigned: (optional principal),
    bid-amount: uint,
    status: (string-ascii 64),
    completion-date: (optional uint),
    inspection-passed: bool
  }
)

(define-map contractors
  { contractor-principal: principal }
  {
    company-name: (string-ascii 128),
    registration-date: uint,
    projects-completed: uint,
    average-rating: uint,
    insurance-verified: bool,
    active-status: bool
  }
)

(define-map ada-compliance-records
  { property-id: uint }
  {
    total-handicap-spaces: uint,
    van-accessible-spaces: uint,
    space-width-compliant: bool,
    signage-compliant: bool,
    access-aisle-compliant: bool,
    last-verification-date: uint,
    verified-by: principal,
    notes: (string-ascii 512)
  }
)

(define-map project-inspections
  { project-id: uint }
  {
    inspection-date: uint,
    inspector: principal,
    workmanship-rating: uint,
    materials-quality: uint,
    compliance-verified: bool,
    defects-noted: (string-ascii 512),
    passed: bool,
    warranty-start: uint
  }
)

(define-map authorized-managers
  { manager-principal: principal }
  {
    authorized: bool,
    authorization-date: uint,
    role: (string-ascii 64)
  }
)

;; Private Functions
(define-private (is-authorized-manager (caller principal))
  (or
    (is-eq caller contract-owner)
    (match (map-get? authorized-managers { manager-principal: caller })
      auth-data (get authorized auth-data)
      false
    )
  )
)

(define-private (is-property-owner (caller principal) (property-id uint))
  (match (map-get? properties { property-id: property-id })
    property-data (is-eq caller (get owner property-data))
    false
  )
)

(define-private (calculate-days-difference (start-date uint) (end-date uint))
  (/ (- end-date start-date) u144)
)

;; Public Functions

;; Register a new property
(define-public (register-property
    (location (string-ascii 256))
    (lot-size uint)
    (parking-capacity uint))
  (let
    (
      (new-property-id (+ (var-get property-id-nonce) u1))
      (current-time block-height)
    )
    (asserts! (> (len location) u0) err-invalid-input)
    (asserts! (> lot-size u0) err-invalid-input)
    (asserts! (> parking-capacity u0) err-invalid-input)
    
    (map-set properties
      { property-id: new-property-id }
      {
        owner: tx-sender,
        location: location,
        lot-size: lot-size,
        parking-capacity: parking-capacity,
        last-striping-date: current-time,
        next-scheduled-date: none,
        ada-compliant: false,
        condition-score: u100
      }
    )
    
    (var-set property-id-nonce new-property-id)
    (var-set total-properties (+ (var-get total-properties) u1))
    (ok new-property-id)
  )
)

;; Schedule a condition assessment
(define-public (schedule-assessment
    (property-id uint)
    (visibility-score uint)
    (wear-rating uint)
    (deficiencies (string-ascii 512))
    (recommended-action (string-ascii 256))
    (urgency-level uint))
  (let
    (
      (new-assessment-id (+ (var-get assessment-id-nonce) u1))
      (current-time block-height)
      (property-data (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
    )
    (asserts! (is-authorized-manager tx-sender) err-unauthorized)
    (asserts! (<= visibility-score u100) err-invalid-input)
    (asserts! (<= wear-rating u100) err-invalid-input)
    (asserts! (<= urgency-level u5) err-invalid-input)
    
    (map-set condition-assessments
      { assessment-id: new-assessment-id }
      {
        property-id: property-id,
        assessment-date: current-time,
        assessor: tx-sender,
        visibility-score: visibility-score,
        wear-rating: wear-rating,
        deficiencies: deficiencies,
        recommended-action: recommended-action,
        urgency-level: urgency-level
      }
    )
    
    ;; Update property condition score
    (map-set properties
      { property-id: property-id }
      (merge property-data { condition-score: (/ (+ visibility-score wear-rating) u2) })
    )
    
    (var-set assessment-id-nonce new-assessment-id)
    (ok new-assessment-id)
  )
)

;; Create a restriping project
(define-public (create-restriping-project
    (property-id uint)
    (scope-description (string-ascii 512))
    (budget-allocated uint)
    (scheduled-start uint))
  (let
    (
      (new-project-id (+ (var-get project-id-nonce) u1))
      (current-time block-height)
      (property-data (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
    )
    (asserts! (or (is-property-owner tx-sender property-id) (is-authorized-manager tx-sender)) err-unauthorized)
    (asserts! (> (len scope-description) u0) err-invalid-input)
    (asserts! (> budget-allocated u0) err-invalid-input)
    
    (map-set restriping-projects
      { project-id: new-project-id }
      {
        property-id: property-id,
        scope-description: scope-description,
        budget-allocated: budget-allocated,
        created-date: current-time,
        scheduled-start: scheduled-start,
        contractor-assigned: none,
        bid-amount: u0,
        status: "pending",
        completion-date: none,
        inspection-passed: false
      }
    )
    
    (var-set project-id-nonce new-project-id)
    (var-set total-projects (+ (var-get total-projects) u1))
    (var-set total-budget-allocated (+ (var-get total-budget-allocated) budget-allocated))
    
    (ok new-project-id)
  )
)

;; Assign contractor to project
(define-public (assign-contractor
    (project-id uint)
    (contractor principal)
    (bid-amount uint))
  (let
    (
      (project-data (unwrap! (map-get? restriping-projects { project-id: project-id }) err-not-found))
      (contractor-data (unwrap! (map-get? contractors { contractor-principal: contractor }) err-not-found))
    )
    (asserts! (is-authorized-manager tx-sender) err-unauthorized)
    (asserts! (get active-status contractor-data) err-unauthorized)
    (asserts! (get insurance-verified contractor-data) err-unauthorized)
    (asserts! (is-none (get contractor-assigned project-data)) err-already-exists)
    
    (map-set restriping-projects
      { project-id: project-id }
      (merge project-data {
        contractor-assigned: (some contractor),
        bid-amount: bid-amount,
        status: "assigned"
      })
    )
    
    (ok true)
  )
)

;; Track project progress
(define-public (track-project-progress
    (project-id uint)
    (new-status (string-ascii 64)))
  (let
    (
      (project-data (unwrap! (map-get? restriping-projects { project-id: project-id }) err-not-found))
      (current-time block-height)
    )
    (asserts! (or (is-authorized-manager tx-sender) 
                  (is-eq (some tx-sender) (get contractor-assigned project-data)))
              err-unauthorized)
    
    (map-set restriping-projects
      { project-id: project-id }
      (merge project-data { status: new-status })
    )
    
    (ok true)
  )
)

;; Verify ADA compliance
(define-public (verify-ada-compliance
    (property-id uint)
    (total-handicap-spaces uint)
    (van-accessible-spaces uint)
    (space-width-compliant bool)
    (signage-compliant bool)
    (access-aisle-compliant bool)
    (notes (string-ascii 512)))
  (let
    (
      (current-time block-height)
      (property-data (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
      (is-compliant (and space-width-compliant signage-compliant access-aisle-compliant))
    )
    (asserts! (is-authorized-manager tx-sender) err-unauthorized)
    
    (map-set ada-compliance-records
      { property-id: property-id }
      {
        total-handicap-spaces: total-handicap-spaces,
        van-accessible-spaces: van-accessible-spaces,
        space-width-compliant: space-width-compliant,
        signage-compliant: signage-compliant,
        access-aisle-compliant: access-aisle-compliant,
        last-verification-date: current-time,
        verified-by: tx-sender,
        notes: notes
      }
    )
    
    ;; Update property compliance status
    (map-set properties
      { property-id: property-id }
      (merge property-data { ada-compliant: is-compliant })
    )
    
    (ok is-compliant)
  )
)

;; Complete project inspection
(define-public (complete-project-inspection
    (project-id uint)
    (workmanship-rating uint)
    (materials-quality uint)
    (compliance-verified bool)
    (defects-noted (string-ascii 512))
    (passed bool))
  (let
    (
      (current-time block-height)
      (project-data (unwrap! (map-get? restriping-projects { project-id: project-id }) err-not-found))
    )
    (asserts! (is-authorized-manager tx-sender) err-unauthorized)
    (asserts! (<= workmanship-rating u100) err-invalid-input)
    (asserts! (<= materials-quality u100) err-invalid-input)
    
    (map-set project-inspections
      { project-id: project-id }
      {
        inspection-date: current-time,
        inspector: tx-sender,
        workmanship-rating: workmanship-rating,
        materials-quality: materials-quality,
        compliance-verified: compliance-verified,
        defects-noted: defects-noted,
        passed: passed,
        warranty-start: current-time
      }
    )
    
    ;; Update project status
    (map-set restriping-projects
      { project-id: project-id }
      (merge project-data {
        status: (if passed "completed" "failed-inspection"),
        completion-date: (some current-time),
        inspection-passed: passed
      })
    )
    
    ;; Update contractor performance if passed
    (if passed
      (match (get contractor-assigned project-data)
        contractor
          (match (map-get? contractors { contractor-principal: contractor })
            contractor-data
              (begin
                (map-set contractors
                  { contractor-principal: contractor }
                  (merge contractor-data {
                    projects-completed: (+ (get projects-completed contractor-data) u1),
                    average-rating: (/ (+ (get average-rating contractor-data) workmanship-rating) u2)
                  })
                )
                (ok true)
              )
            (ok true)
          )
        (ok true)
      )
      (ok true)
    )
  )
)

;; Register contractor
(define-public (register-contractor
    (company-name (string-ascii 128))
    (insurance-verified bool))
  (let
    (
      (current-time block-height)
    )
    (asserts! (> (len company-name) u0) err-invalid-input)
    
    (map-set contractors
      { contractor-principal: tx-sender }
      {
        company-name: company-name,
        registration-date: current-time,
        projects-completed: u0,
        average-rating: u0,
        insurance-verified: insurance-verified,
        active-status: true
      }
    )
    
    (ok true)
  )
)

;; Authorize property manager
(define-public (authorize-manager
    (manager principal)
    (role (string-ascii 64)))
  (let
    (
      (current-time block-height)
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set authorized-managers
      { manager-principal: manager }
      {
        authorized: true,
        authorization-date: current-time,
        role: role
      }
    )
    
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-property-details (property-id uint))
  (ok (map-get? properties { property-id: property-id }))
)

(define-read-only (get-project-details (project-id uint))
  (ok (map-get? restriping-projects { project-id: project-id }))
)

(define-read-only (get-assessment-details (assessment-id uint))
  (ok (map-get? condition-assessments { assessment-id: assessment-id }))
)

(define-read-only (get-compliance-status (property-id uint))
  (ok (map-get? ada-compliance-records { property-id: property-id }))
)

(define-read-only (get-contractor-info (contractor principal))
  (ok (map-get? contractors { contractor-principal: contractor }))
)

(define-read-only (get-inspection-results (project-id uint))
  (ok (map-get? project-inspections { project-id: project-id }))
)

(define-read-only (get-total-statistics)
  (ok {
    total-properties: (var-get total-properties),
    total-projects: (var-get total-projects),
    total-budget-allocated: (var-get total-budget-allocated)
  })
)

(define-read-only (check-authorization (manager principal))
  (ok (map-get? authorized-managers { manager-principal: manager }))
)


;; title: parking-striping-coordinator
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

