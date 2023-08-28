(defpackage :lem-vi-mode/text-objects
  (:use :cl
        :lem)
  (:import-from :lem-vi-mode/core
                :make-range
                :text-object-abort)
  (:import-from :lem-vi-mode/visual
                :visual
                :visual-p
                :visual-char-p
                :visual-range
                :vi-visual-char)
  (:import-from :lem-vi-mode/word
                :word-char-type)
  (:export :text-object
           :function-text-object
           :surrounded-text-object
           :quoted-text-object
           :a-range-of
           :inner-range-of

           :word-object))
(in-package :lem-vi-mode/text-objects)

(defclass text-object () ())

(defclass function-text-object (text-object)
  ((function :type function
             :initarg :function)))

(defclass block-text-object (text-object)
  ((open-char :type character
              :initarg :open-char)
   (close-char :type character
               :initarg :close-char)
   (escape-char :type (or null character)
                :initarg :escape-char
                :initform #\\)))

(defclass quoted-text-object (text-object)
  ((quote-char :type character
               :initarg :quote-char)
   (escape-char :type (or null character)
                :initarg :escape-char
                :initform #\\)))

(defgeneric a-range-of (object state count)
  (:method ((object symbol) state count)
    (a-range-of (make-instance object) state count)))

(defgeneric inner-range-of (object state count)
  (:method ((object symbol) state count)
    (inner-range-of (make-instance object) state count)))

(defun target-region ()
  (if (visual-p)
      (visual-range)
      (list (copy-point (current-point))
            (copy-point (current-point)))))

(defmethod a-range-of ((object function-text-object) state count)
  (declare (ignore state))
  (with-slots (function) object
    (destructuring-bind (beg end)
        (target-region)
      (let* ((direction (cond
                          ((point< beg end) :forward)
                          ((point< end beg) :backward)))
             (char-type (if (eq direction :backward)
                            (funcall function (character-at end -1))
                            (funcall function (character-at end))))
             (initial-char-type char-type)
             (check-fn (lambda (c) (eq (funcall function c) char-type)))
             (buffer (point-buffer end)))
        (labels ((%move-forward (p)
                   (loop with buffer-end = (buffer-end-point buffer)
                         if (or (point= p buffer-end)
                                (char= (character-at p) #\Newline))
                         do (return nil)
                         else if (funcall check-fn (character-at p))
                         do (character-offset p 1)
                         else
                         do (return t)))
                 (%move-backward (p)
                   (loop while (and (< 0 (point-charpos p))
                                    (funcall check-fn (character-at p -1)))
                         do (character-offset p -1))
                   p)
                 (move-forward ()
                   (if (eq direction :backward)
                       (%move-backward end)
                       (%move-forward end)))
                 (move-backward ()
                   (if (eq direction :backward)
                       (%move-forward beg)
                       (%move-backward beg)))
                 (skip-spaces-forward (&optional include-newline)
                   (if (eq direction :backward)
                       (skip-chars-backward end (if include-newline
                                                    '(#\Space #\Tab #\Newline)
                                                    '(#\Space #\Tab)))
                       (skip-chars-forward end (if include-newline
                                                   '(#\Space #\Tab #\Newline)
                                                   '(#\Space #\Tab)))))
                 (skip-spaces-backward ()
                   (if (eq direction :backward)
                       (skip-chars-forward beg '(#\Space #\Tab))
                       (skip-chars-backward beg '(#\Space #\Tab))))
                 (offset ()
                   (if (eq direction :backward) -1 0))
                 (dead-end-p ()
                   (or (point= end (if (eq direction :backward)
                                       (buffer-start-point buffer)
                                       (buffer-end-point buffer)))
                       (char= (character-at end (offset))
                              #\Newline))))
          (if (eq char-type :blank)
              (progn
                (when (null direction)
                  (skip-chars-backward beg '(#\Space #\Tab #\Newline)))
                (skip-spaces-forward t))
              (move-backward))
          (dotimes (i count)
            (skip-spaces-forward t)
            (when (dead-end-p)
              (error 'text-object-abort
                     :range (make-range beg end)))
            (setf char-type
                  (funcall function (character-at end (offset))))
            (move-forward))
          (unless (eq initial-char-type :blank)
            (if (dead-end-p)
                (skip-spaces-backward)
                (skip-spaces-forward)))))
      (make-range beg end))))

(defmethod inner-range-of ((object function-text-object) state count)
  (declare (ignore state))
  (with-slots (function) object
    (destructuring-bind (beg end)
        (target-region)
      (let* ((direction (cond
                          ((point< beg end) :forward)
                          ((point< end beg) :backward)))
             (char-type (funcall function (character-at end)))
             (check-fn (lambda (c) (eq (funcall function c) char-type)))
             (buffer (point-buffer beg)))
        (flet ((move-forward (p)
                 (loop with buffer-end = (buffer-end-point (point-buffer p))
                       while (and (point/= p buffer-end)
                                  (char/= (character-at p) #\Newline)
                                  (funcall check-fn (character-at p)))
                       do (character-offset p 1))
                 p)
               (move-backward (p)
                 (loop while (and (< 0 (point-charpos p))
                                  (funcall check-fn (character-at p -1)))
                       do (character-offset p -1))
                 p))
          (if (or (null direction)
                  (eq direction :forward))
              (progn
                (move-backward beg)
                (dotimes (i count)
                  (when (or (point= end (buffer-end-point buffer))
                            (char= (character-at end) #\Newline))
                    (error 'text-object-abort
                           :range (make-range beg end)))
                  (move-forward end)
                  (setf char-type (funcall function (character-at end)))))
              (progn
                (move-forward beg)
                (dotimes (i count)
                  (when (or (point= end (buffer-start-point buffer))
                            (char= (character-at end -1) #\Newline))
                    (error 'text-object-abort
                           :range (make-range beg end)))
                  (move-backward end)
                  (setf char-type (funcall function (character-at end -1))))))
          (make-range beg end))))))

(defmethod a-range-of ((object quoted-text-object) state count)
  (declare (ignore state count))
  (with-slots (quote-char escape-char) object
    (destructuring-bind (beg end)
        (target-region)
      (let ((direction (cond
                         ((point< beg end) :forward)
                         ((point< end beg) :backward))))
        (loop
          (skip-chars-backward beg (lambda (c) (char/= c quote-char)))
          (let ((prev-char (character-at beg -1)))
            (cond
              ;; No quote-char found
              ((null prev-char)
               (keyboard-quit))
              ;; Skip escaped quote-char
              ((and escape-char
                    (char= prev-char escape-char)))
              ;; Successfully found
              (t
               (character-offset beg -1)
               (return)))))
        (loop
          (skip-chars-forward end (lambda (c) (char/= c quote-char)))
          (let ((next-char (character-at end)))
            (cond
              ;; No quote-char found
              ((null next-char)
               (keyboard-quit))
              ;; Skip escaped quote-char
              ((and escape-char
                    (char= (character-at end -1) escape-char)))
              ;; Successfully found
              (t
               (character-offset end 1)
               (return)))))
        (if (member (character-at end) '(#\Space #\Tab))
            (skip-chars-forward end '(#\Space #\Tab))
            (skip-chars-backward beg '(#\Space #\Tab))))
      (make-range beg end))))

(defmethod a-range-of ((object quoted-text-object) (state visual) count)
  (declare (ignore count))
  (with-slots (open-char escape-char) object
    (destructuring-bind (beg end)
        (visual-range)
      (let ((direction (cond
                         ((point< beg end) :forward)
                         ((point< end beg) :backward))))
        (loop
          (skip-chars-backward beg (lambda (c) (char/= c open-char)))
          (unless (char= (character-at beg -1) escape-char)
            (character-offset beg -1)
            (return)))
        (loop
          (skip-chars-forward end (lambda (c) (char/= c open-char)))
          (unless (char= (character-at end -1) escape-char)
            (character-offset end 1)
            (return)))
        (if (member (character-at end) '(#\Space #\Tab))
            (skip-chars-forward end '(#\Space #\Tab))
            (skip-chars-backward beg '(#\Space #\Tab))))
      (make-range beg end))))

(defclass word-object (function-text-object) ()
  (:default-initargs
   :function #'word-char-type))

(defmethod a-range-of :before ((object word-object) (state visual) count)
  (unless (visual-char-p)
    (vi-visual-char)))

(defmethod inner-range-of :before ((object word-object) (state visual) count)
  (unless (visual-char-p)
    (vi-visual-char)))
