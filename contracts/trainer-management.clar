;; Trainer Management Contract
;; Handles trainer registration, certification, and reputation management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TRAINER-EXISTS (err u101))
(define-constant ERR-TRAINER-NOT-FOUND (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-INVALID-RATING (err u104))
(define-constant ERR-SELF-RATING (err u105))

;; Data Variables
(define-data-var next-trainer-id uint u1)

;; Data Maps
(define-map trainers principal {
  trainer-id: uint,
  name: (string-ascii 100),
  certifications: (list 10 (string-ascii 50)),
  specializations: (list 10 (string-ascii 50)),
  hourly-rate: uint,
  total-ratings: uint,
  rating-sum: uint,
  is-verified: bool,
  is-active: bool,
  registration-time: uint
})

(define-map trainer-ratings {trainer: principal, rater: principal} {
  rating: uint,
  timestamp: uint
})

;; Public Functions

;; Register a new trainer
(define-public (register-trainer
  (name (string-ascii 100))
  (certifications (list 10 (string-ascii 50)))
  (specializations (list 10 (string-ascii 50)))
  (hourly-rate uint))
  (let ((trainer-id (var-get next-trainer-id)))
    (asserts! (is-none (map-get? trainers tx-sender)) ERR-TRAINER-EXISTS)
    (asserts! (and (> (len name) u0) (<= (len name) u100)) ERR-INVALID-INPUT)
    (asserts! (and (> hourly-rate u0) (<= hourly-rate u1000)) ERR-INVALID-INPUT)

    (map-set trainers tx-sender {
      trainer-id: trainer-id,
      name: name,
      certifications: certifications,
      specializations: specializations,
      hourly-rate: hourly-rate,
      total-ratings: u0,
      rating-sum: u0,
      is-verified: false,
      is-active: true,
      registration-time: block-height
    })

    (var-set next-trainer-id (+ trainer-id u1))
    (ok trainer-id)))

;; Rate a trainer
(define-public (rate-trainer (trainer principal) (rating uint))
  (let ((trainer-data (unwrap! (map-get? trainers trainer) ERR-TRAINER-NOT-FOUND)))
    (asserts! (not (is-eq trainer tx-sender)) ERR-SELF-RATING)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)

    (let ((existing-rating (map-get? trainer-ratings {trainer: trainer, rater: tx-sender})))
      (match existing-rating
        prev-rating
        ;; Update existing rating
        (let ((old-rating (get rating prev-rating))
              (new-rating-sum (+ (- (get rating-sum trainer-data) old-rating) rating)))
          (map-set trainer-ratings {trainer: trainer, rater: tx-sender} {
            rating: rating,
            timestamp: block-height
          })
          (map-set trainers trainer (merge trainer-data {
            rating-sum: new-rating-sum
          }))
          (ok true))
        ;; New rating
        (begin
          (map-set trainer-ratings {trainer: trainer, rater: tx-sender} {
            rating: rating,
            timestamp: block-height
          })
          (map-set trainers trainer (merge trainer-data {
            total-ratings: (+ (get total-ratings trainer-data) u1),
            rating-sum: (+ (get rating-sum trainer-data) rating)
          }))
          (ok true))))))

;; Update trainer profile
(define-public (update-trainer-profile
  (name (string-ascii 100))
  (specializations (list 10 (string-ascii 50)))
  (hourly-rate uint))
  (let ((trainer-data (unwrap! (map-get? trainers tx-sender) ERR-TRAINER-NOT-FOUND)))
    (asserts! (and (> (len name) u0) (<= (len name) u100)) ERR-INVALID-INPUT)
    (asserts! (and (> hourly-rate u0) (<= hourly-rate u1000)) ERR-INVALID-INPUT)

    (map-set trainers tx-sender (merge trainer-data {
      name: name,
      specializations: specializations,
      hourly-rate: hourly-rate
    }))
    (ok true)))

;; Verify trainer (admin only)
(define-public (verify-trainer (trainer principal))
  (let ((trainer-data (unwrap! (map-get? trainers trainer) ERR-TRAINER-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set trainers trainer (merge trainer-data {
      is-verified: true
    }))
    (ok true)))

;; Deactivate trainer
(define-public (deactivate-trainer)
  (let ((trainer-data (unwrap! (map-get? trainers tx-sender) ERR-TRAINER-NOT-FOUND)))
    (map-set trainers tx-sender (merge trainer-data {
      is-active: false
    }))
    (ok true)))

;; Read-only Functions

;; Get trainer info
(define-read-only (get-trainer (trainer principal))
  (map-get? trainers trainer))

;; Get trainer rating
(define-read-only (get-trainer-rating (trainer principal))
  (match (map-get? trainers trainer)
    trainer-data
    (if (> (get total-ratings trainer-data) u0)
      (some (/ (get rating-sum trainer-data) (get total-ratings trainer-data)))
      none)
    none))

;; Check if trainer is verified
(define-read-only (is-trainer-verified (trainer principal))
  (match (map-get? trainers trainer)
    trainer-data (get is-verified trainer-data)
    false))

;; Get user's rating for a trainer
(define-read-only (get-user-rating (trainer principal) (rater principal))
  (map-get? trainer-ratings {trainer: trainer, rater: rater}))
