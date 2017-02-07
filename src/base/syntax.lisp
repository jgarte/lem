(in-package :lem-base)

(export '(*global-syntax-highlight*
          enable-syntax-highlight
          enable-syntax-highlight-p
          syntax-table
          fundamental-syntax-table
          make-syntax-table
          make-syntax-test
          syntax-add-match
          syntax-add-region
          syntax-word-char-p
          syntax-space-char-p
          syntax-symbol-char-p
          syntax-open-paren-char-p
          syntax-closed-paren-char-p
          syntax-string-quote-char-p
          syntax-escape-char-p
          syntax-expr-prefix-char-p
          syntax-skip-expr-prefix-forward
          syntax-skip-expr-prefix-backward
          syntax-scan-range
          in-string-p
          in-comment-p
          search-comment-start-forward
          search-comment-start-backward
          search-string-start-forward
          search-string-start-backward
          skip-whitespace-forward
          skip-whitespace-backward
          skip-space-and-comment-forward
          skip-space-and-comment-backward
          symbol-string-at-point
          form-offset
          scan-lists))

(define-editor-variable enable-syntax-highlight nil)
(defvar *global-syntax-highlight* t)

(defstruct (syntax-test (:constructor %make-syntax-test))
  thing
  word-p)

(defun make-syntax-test (thing &key word-p)
  (%make-syntax-test :thing (ppcre:create-scanner thing)
                     :word-p word-p))

(defclass syntax ()
  ((attribute
    :initarg :attribute
    :initform 0
    :reader syntax-attribute
    :type (or null attribute))))

(defclass syntax-region (syntax)
  ((start
    :initarg :start
    :reader syntax-region-start
    :type syntax-test)
   (end
    :initarg :end
    :reader syntax-region-end
    :type syntax-test)))

(defclass syntax-match (syntax)
  ((test
    :initarg :test
    :initform nil
    :reader syntax-match-test)
   (test-symbol
    :initarg :test-symbol
    :initform nil
    :reader syntax-match-test-symbol)
   (end-symbol
    :initarg :end-symbol
    :initform nil
    :reader syntax-match-end-symbol)
   (matched-symbol
    :initarg :matched-symbol
    :initform nil
    :reader syntax-match-matched-symbol)
   (symbol-lifetime
    :initarg :symbol-lifetime
    :initform nil
    :reader syntax-match-symbol-lifetime)
   (move-action
    :initarg :move-action
    :initform nil
    :reader syntax-match-move-action)))

(defstruct (syntax-table (:constructor %make-syntax-table))
  (space-chars '(#\space #\tab #\newline))
  (symbol-chars '(#\_))
  (paren-alist '((#\( . #\))
                 (#\[ . #\])
                 (#\{ . #\})))
  (string-quote-chars '(#\"))
  (escape-chars '(#\\))
  expr-prefix-chars
  expr-prefix-forward-function
  expr-prefix-backward-function
  line-comment-string
  block-comment-pairs
  region-list
  match-list)

(defun make-syntax-table (&rest args)
  (let ((syntax-table (apply '%make-syntax-table args)))
    (let ((string (syntax-table-line-comment-string syntax-table)))
      (when string
        (syntax-add-region syntax-table
                           (make-syntax-test `(:sequence ,string))
                           (make-syntax-test "$")
                           :attribute *syntax-comment-attribute*)))
    (dolist (string-quote-char (syntax-table-string-quote-chars syntax-table))
      (syntax-add-region syntax-table
                         (make-syntax-test `(:sequence ,(string string-quote-char)))
                         (make-syntax-test `(:sequence ,(string string-quote-char)))
                         :attribute *syntax-string-attribute*))
    (loop :for (start . end) :in (syntax-table-block-comment-pairs syntax-table)
          :do (syntax-add-region syntax-table
                                 (make-syntax-test `(:sequence ,start))
                                 (make-syntax-test `(:sequence ,end))
                                 :attribute *syntax-comment-attribute*))
    syntax-table))

(defun syntax-add-match (syntax-table test
                                      &key test-symbol end-symbol attribute
                                      matched-symbol (symbol-lifetime -1) move-action)
  (push (make-instance 'syntax-match
                       :test test
                       :test-symbol test-symbol
                       :end-symbol end-symbol
                       :attribute attribute
                       :matched-symbol matched-symbol
                       :symbol-lifetime symbol-lifetime
                       :move-action move-action)
        (syntax-table-match-list syntax-table))
  t)

(defun syntax-add-region (syntax-table start end &key attribute)
  (push (make-instance 'syntax-region
                       :start start
                       :end end
                       :attribute attribute)
        (syntax-table-region-list syntax-table)))

(defvar *fundamental-syntax-table* (make-syntax-table))

(defun fundamental-syntax-table ()
  *fundamental-syntax-table*)

(defvar *current-syntax* nil)

(defun current-syntax ()
  (or *current-syntax*
      (buffer-syntax-table (current-buffer))))

(defun syntax-word-char-p (c)
  (and (characterp c)
       (alphanumericp c)))

(defun syntax-space-char-p (c)
  (member c (syntax-table-space-chars (current-syntax))))

(defun syntax-symbol-char-p (c)
  (or (syntax-word-char-p c)
      (member c (syntax-table-symbol-chars (current-syntax)))))

(defun syntax-open-paren-char-p (c)
  (assoc c (syntax-table-paren-alist (current-syntax))))

(defun syntax-closed-paren-char-p (c)
  (rassoc c (syntax-table-paren-alist (current-syntax))))

(defun syntax-equal-paren-p (x y)
  (flet ((f (c)
	   (if (syntax-open-paren-char-p c)
	       c
               (car (rassoc c (syntax-table-paren-alist (current-syntax)))))))
    (eql (f x) (f y))))

(defun syntax-string-quote-char-p (c)
  (member c (syntax-table-string-quote-chars (current-syntax))))

(defun syntax-escape-char-p (c)
  (member c (syntax-table-escape-chars (current-syntax))))

(defun syntax-expr-prefix-char-p (c)
  (member c (syntax-table-expr-prefix-chars (current-syntax))))

(defun syntax-skip-expr-prefix-forward (point)
  (let ((f (syntax-table-expr-prefix-forward-function (current-syntax))))
    (if f (funcall f point) t)))

(defun syntax-skip-expr-prefix-backward (point)
  (let ((f (syntax-table-expr-prefix-backward-function (current-syntax))))
    (if f (funcall f point) t)))

(defun %syntax-string-match (str1 str2 str1-pos)
  (let ((end1 (+ str1-pos (length str2))))
    (when (and (<= end1 (length str1))
               (string= str1 str2
                        :start1 str1-pos
                        :end1 end1))
      (length str2))))

(defun syntax-line-comment-p (line-string pos)
  (%syntax-string-match line-string
                        (syntax-table-line-comment-string (current-syntax))
                        pos))

(defun syntax-start-block-comment-p (point)
  (let ((line-string (line-string point))
        (pos (point-charpos point)))
    (dolist (pair (syntax-table-block-comment-pairs (current-syntax)))
      (let ((start (car pair)))
        (let ((result (%syntax-string-match line-string start pos)))
          (when result
            (return (values result pair))))))))

(defun syntax-end-block-comment-p (point)
  (dolist (pair (syntax-table-block-comment-pairs (current-syntax)))
    (let ((end (cdr pair)))
      (with-point ((point point))
        (character-offset point (- (length end)))
        (let ((result (%syntax-string-match (line-string point)
                                            end
                                            (point-charpos point))))
          (when result
            (return (values result pair))))))))


(defun enable-syntax-highlight-p (buffer)
  (and *global-syntax-highlight*
       (value 'enable-syntax-highlight :buffer buffer)))

(defvar *syntax-scan-limit*)
(defvar *syntax-symbol-lifetimes* nil)

(defun syntax-update-symbol-lifetimes ()
  (setq *syntax-symbol-lifetimes*
        (loop :for (symbol . lifetime) :in *syntax-symbol-lifetimes*
	   :when (/= 0 lifetime)
	   :collect (cons symbol (1- lifetime)))))

(defun syntax-test-match-p (syntax-test point &optional optional-key optional-value)
  (let ((string (line-string point)))
    (multiple-value-bind (start end)
        (ppcre:scan (syntax-test-thing syntax-test)
                    string
                    :start (point-charpos point))
      (when (and start
                 (= (point-charpos point) start)
                 (or (not (syntax-test-word-p syntax-test))
                     (<= (length string) end)
                     (not (syntax-symbol-char-p (schar string end)))))
        (if optional-key
            (with-point ((start-point point))
              (line-offset point 0 end)
              (put-text-property start-point point optional-key optional-value))
            (line-offset point 0 end))
        point))))

(defun syntax-scan-region (region point start-charpos)
  (do ((start-charpos start-charpos 0)) (nil)
    (loop
      (cond ((syntax-escape-char-p (character-at point 0))
             (character-offset point 1))
            ((syntax-test-match-p (syntax-region-end region) point 'region-side :end)
             (line-add-property (point-line point)
                                start-charpos (point-charpos point)
                                :attribute (syntax-attribute region)
                                nil)
             (setf (line-%syntax-context (point-line point)) nil)
             (return-from syntax-scan-region (values point t)))
            ((end-line-p point)
             (return)))
      (character-offset point 1))
    (line-add-property (point-line point)
                       start-charpos (line-length (point-line point))
                       :attribute (syntax-attribute region)
                       t)
    (setf (line-%syntax-context (point-line point)) region)
    (unless (line-offset point 1)
      (return-from syntax-scan-region point))
    (when (point<= *syntax-scan-limit* point)
      (return-from syntax-scan-region point))))

(defun syntax-scan-move-action (syntax start)
  (with-point ((end start)
               (cur start))
    (let ((end (funcall (syntax-match-move-action syntax) end)))
      (when (and end (point< cur end))
        (loop :until (same-line-p cur end) :do
              (setf (line-%syntax-context (point-line cur)) syntax)
              (line-offset cur 1))
        (setf (line-%syntax-context (point-line cur)) 'end-move-action)
        (when (syntax-attribute syntax)
          (put-text-property start end :attribute (syntax-attribute syntax)))
        end))))

(defun syntax-scan-token-test (syntax point)
  (etypecase syntax
    (syntax-region
     (let ((start-charpos (point-charpos point))
           (point (syntax-test-match-p (syntax-region-start syntax) point 'region-side :start)))
       (when point
         (syntax-scan-region syntax point start-charpos)
         point)))
    (syntax-match
     (when (or (not (syntax-match-test-symbol syntax))
               (find (syntax-match-test-symbol syntax)
                     *syntax-symbol-lifetimes*
                     :key #'car))
       (with-point ((start point))
         (when (syntax-test-match-p (syntax-match-test syntax) point)
           (when (syntax-match-matched-symbol syntax)
             (push (cons (syntax-match-matched-symbol syntax)
                         (syntax-match-symbol-lifetime syntax))
                   *syntax-symbol-lifetimes*))
           (when (syntax-match-end-symbol syntax)
             (setf *syntax-symbol-lifetimes*
                   (delete (syntax-match-end-symbol syntax)
                           *syntax-symbol-lifetimes*
                           :key #'car)))
           (cond
             ((syntax-match-move-action syntax)
              (let ((goal-point (syntax-scan-move-action syntax start)))
                (when goal-point
                  (move-point point goal-point))))
             ((syntax-attribute syntax)
              (put-text-property start point :attribute (syntax-attribute syntax))
              point)
             (t
              point))))))))

(defun syntax-maybe-scan-region (point)
  (let* ((line (point-line point))
         (prev (line-prev line))
         (syntax (and prev (line-%syntax-context prev))))
    (if (null syntax)
        (setf (line-%syntax-context line) nil)
        (cond
          ((typep syntax 'syntax-region)
           (syntax-scan-region syntax point (point-charpos point)))
          ((typep syntax 'syntax)
           (cond ((eq (line-%syntax-context line) 'end-move-action)
                  (with-point ((cur point))
                    (previous-single-property-change cur :attribute)
                    (let ((goal-point (syntax-scan-move-action syntax cur)))
                      (when goal-point
                        (move-point point goal-point)))))
                 (t
                  (line-add-property (point-line point)
                                     0 (line-length line)
                                     :attribute (syntax-attribute syntax)
                                     t)
                  (line-end point))))
          (t (setf (line-%syntax-context line) nil))))))

(defun syntax-scan-line (point limit)
  (let ((*syntax-scan-limit* limit))
    (syntax-maybe-scan-region point)
    (loop :until (or (end-line-p point)
                     (point<= *syntax-scan-limit* point))
          :do
          (skip-chars-forward point (lambda (c)
                                      (and (syntax-space-char-p c)
                                           (char/= c #\newline))))
          (when (end-line-p point) (return))
          (when (cond ((syntax-escape-char-p (character-at point 0))
                       (unless (character-offset point 2)
                         (buffer-end point)
                         (return))
                       nil)
                      ((dolist (syn (syntax-table-region-list (current-syntax)))
                         (when (syntax-scan-token-test syn point)
                           (return t))))
                      ((dolist (syn (syntax-table-match-list (current-syntax)))
                         (when (syntax-scan-token-test syn point)
                           (return t))))
                      (t
                       (character-offset point 1)
                       (skip-chars-forward point #'syntax-symbol-char-p)
                       t))
            (syntax-update-symbol-lifetimes)))
    (setf (line-%symbol-lifetimes (point-line point))
          *syntax-symbol-lifetimes*)
    (or (line-offset point 1)
        (buffer-end point))))

(defun syntax-scan-range (start end)
  (assert (eq (point-buffer start)
              (point-buffer end)))
  (let ((buffer (point-buffer start)))
    (when (enable-syntax-highlight-p buffer)
      (let ((*current-syntax*
             (buffer-syntax-table buffer))
            (*syntax-symbol-lifetimes*
             (let ((prev (line-prev (point-line start))))
               (and prev (line-%symbol-lifetimes prev)))))
        (with-point ((start start)
                     (end end))
          (line-start start)
          (line-end end)
          (loop
            (line-clear-property (point-line start) :attribute)
            (syntax-scan-line start end)
            (when (point<= end start)
              (return start))))))))


(defmacro with-point-syntax (point &body body)
  `(let ((*current-syntax* (buffer-syntax-table (point-buffer ,point))))
     ,@body))

(defun in-string-p (point)
  (with-point-syntax point
    (and (eq *syntax-string-attribute*
             (text-property-at point :attribute))
         (not (eq :start (text-property-at point 'region-side))))))

(defun in-comment-p (point)
  (with-point-syntax point
    (and (eq *syntax-comment-attribute*
             (text-property-at point :attribute))
         (not (eq :start (text-property-at point 'region-side))))))

(defun %search-syntax-start-forward (point syntax limit)
  (with-point ((curr point))
    (loop
      (unless (next-single-property-change curr :attribute limit)
        (return nil))
      (when (and (eq syntax
                     (text-property-at curr :attribute))
                 (eq :start (text-property-at curr 'region-side)))
        (return (move-point point curr))))))

(defun %search-syntax-start-backward (point syntax limit)
  (with-point ((curr point))
    (loop
      (unless (previous-single-property-change curr :attribute limit)
        (return nil))
      (when (and (eq syntax
                     (text-property-at curr :attribute))
                 (eq :start (text-property-at curr 'region-side)))
        (return (move-point point curr))))))

(defun search-comment-start-forward (point &optional limit)
  (%search-syntax-start-forward point *syntax-comment-attribute* limit))

(defun search-comment-start-backward (point &optional limit)
  (%search-syntax-start-backward point *syntax-comment-attribute* limit))

(defun search-string-start-forward (point &optional limit)
  (%search-syntax-start-forward point *syntax-string-attribute* limit))

(defun search-string-start-backward (point &optional limit)
  (%search-syntax-start-backward point *syntax-string-attribute* limit))


(defun skip-whitespace-forward (point)
  (with-point-syntax point
    (skip-chars-forward point #'syntax-space-char-p)))

(defun skip-whitespace-backward (point)
  (with-point-syntax point
    (skip-chars-backward point #'syntax-space-char-p)))

(defun skip-space-and-comment-forward (point)
  (with-point-syntax point
    (loop
      (skip-chars-forward point #'syntax-space-char-p)
      (multiple-value-bind (result success)
          (%skip-comment-forward point)
        (unless result
          (return success))))))

(defun skip-space-and-comment-backward (point)
  (with-point-syntax point
    (if (%position-line-comment (line-string point) (point-charpos point) nil)
        (skip-chars-backward point #'syntax-space-char-p)
        (loop
          (skip-chars-backward point #'syntax-space-char-p)
          (multiple-value-bind (result success)
              (%skip-comment-backward point)
            (unless result
              (return success)))))))

(defun symbol-string-at-point (point)
  (with-point-syntax point
    (with-point ((point point))
      (skip-chars-backward point #'syntax-symbol-char-p)
      (unless (syntax-symbol-char-p (character-at point))
        (return-from symbol-string-at-point nil))
      (with-point ((start point))
        (skip-chars-forward point #'syntax-symbol-char-p)
        (points-to-string start point)))))


(defun %skip-comment-forward (point)
  (multiple-value-bind (n pair)
      (syntax-start-block-comment-p point)
    (cond (n
           (with-point ((curr1 point)
                        (curr2 point))
             (character-offset curr1 n)
             (character-offset curr2 n)
             (let ((depth 1))
               (unless (search-forward curr2 (cdr pair))
                 (return-from %skip-comment-forward (values nil nil)))
               (unless (search-forward curr1 (car pair))
                 (return-from %skip-comment-forward (values (move-point point curr2) t)))
               (loop
                 (cond ((and curr1 (point< curr1 curr2))
                        (incf depth)
                        (unless (search-forward curr1 (car pair))
                          (setq curr1 nil)))
                       (t
                        (when (= 0 (decf depth))
                          (return-from %skip-comment-forward (values (move-point point curr2) t)))
                        (unless (search-forward curr2 (cdr pair))
                          (return-from %skip-comment-forward (values nil nil)))))))))
          ((syntax-line-comment-p (line-string point)
                                  (point-charpos point))
           (values (line-offset point 1) t))
          (t
           (values nil t)))))

(defun %position-line-comment (string end instr)
  (loop :for i := 0 :then (1+ i)
        :while (< i end)
        :do (let ((c (schar string i)))
              (if instr
                  (cond ((syntax-escape-char-p c)
                         (incf i))
                        ((syntax-string-quote-char-p c)
                         (setf instr nil)))
                  (cond ((syntax-line-comment-p string i)
                         (return i))
                        ((syntax-escape-char-p c)
                         (incf i))
                        ((syntax-string-quote-char-p c)
                         (setf instr t)))))
        :finally (if instr
                     (return (%position-line-comment string end t))
                     (return nil))))

(defun %skip-comment-backward (point)
  (multiple-value-bind (n pair)
      (syntax-end-block-comment-p point)
    (if n
        (with-point ((curr1 point)
                     (curr2 point))
          (character-offset curr1 (- n))
          (character-offset curr2 (- n))
          (let ((depth 1))
            (unless (search-backward curr1 (car pair))
              (return-from %skip-comment-backward (values nil nil)))
            (unless (search-backward curr2 (cdr pair))
              (return-from %skip-comment-backward (values (move-point point curr1) t)))
            (loop
              (cond ((and curr2 (point< curr1 curr2))
                     (incf depth)
                     (unless (search-backward curr2 (cdr pair))
                       (setq curr2 nil)))
                    (t
                     (when (= 0 (decf depth))
                       (return-from %skip-comment-backward (values (move-point point curr1) t)))
                     (unless (search-backward curr1 (car pair))
                       (return-from %skip-comment-backward (values nil nil))))))))
        (let ((line-comment-pos (%position-line-comment (line-string point) (point-charpos point) nil)))
          (if line-comment-pos
              (values (line-offset point 0 line-comment-pos) t)
              (values nil t))))))

(defun %sexp-escape-p (point offset)
  (let ((count 0))
    (loop :with string := (line-string point)
          :for i :downfrom (+ (1- (point-charpos point)) offset) :to 0
          :do (if (syntax-escape-char-p (schar string i))
                  (incf count)
                  (return)))
    (values (oddp count) count)))

(defun %sexp-symbol-p (c)
  (or (syntax-symbol-char-p c)
      (syntax-escape-char-p c)
      (syntax-expr-prefix-char-p c)))

(defun %skip-symbol-forward (point)
  (loop :for c := (character-at point 0)
        :do
        (cond ((syntax-escape-char-p c)
               (character-offset point 1))
              ((not (or (syntax-symbol-char-p c)
                        (syntax-expr-prefix-char-p c)))
               (return)))
        (unless (character-offset point 1)
          (return)))
  point)

(defun %skip-symbol-backward (point)
  (loop :for c := (character-at point -1)
        :do (multiple-value-bind (escape-p skip-count)
                (%sexp-escape-p point -1)
              (cond (escape-p
                     (character-offset point (- (1+ skip-count))))
                    ((or (syntax-symbol-char-p c)
                         (syntax-expr-prefix-char-p c)
                         (syntax-escape-char-p c))
                     (character-offset point -1))
                    (t
                     (return)))))
  point)

(defun %skip-string-forward (point)
  (loop :with quote-char := (character-at point 0) :do
     (unless (character-offset point 1)
       (return nil))
     (let ((c (character-at point)))
       (cond ((syntax-escape-char-p c)
	      (character-offset point 1))
	     ((and (syntax-string-quote-char-p c)
		   (char= c quote-char))
	      (character-offset point 1)
	      (return point))))))

(defun %skip-string-backward (point)
  (character-offset point -1)
  (loop :with quote-char := (character-at point) :do
     (unless (character-offset point -1)
       (return nil))
     (if (%sexp-escape-p point 0)
	 (character-offset point -1)
	 (let ((c (character-at point)))
	   (cond ((and (syntax-string-quote-char-p c)
		       (char= c quote-char))
		  (return point)))))))

(defun %skip-list-forward (point depth)
  (loop :with paren-stack := '() :do
     (unless (skip-space-and-comment-forward point)
       (return nil))
     (when (end-buffer-p point)
       (return nil))
     (let ((c (character-at point 0)))
       (cond ((syntax-open-paren-char-p c)
	      (push c paren-stack)
	      (character-offset point 1)
	      (when (zerop (incf depth))
		(return point)))
	     ((syntax-closed-paren-char-p c)
	      (unless (or (and (< 0 depth)
			       (null paren-stack))
			  (syntax-equal-paren-p c (car paren-stack)))
		(return nil))
	      (pop paren-stack)
	      (character-offset point 1)
	      (when (zerop (decf depth))
		(return point)))
	     ((syntax-string-quote-char-p c)
	      (%skip-string-forward point))
	     ((syntax-escape-char-p c)
              (unless (character-offset point 2)
                (return nil)))
	     (t
	      (character-offset point 1))))))

(defun %skip-list-backward (point depth)
  (loop :with paren-stack := '() :do
     (unless (skip-space-and-comment-backward point)
       (return nil))
     (when (start-buffer-p point)
       (return nil))
     (let ((c (character-at point -1)))
       (cond ((%sexp-escape-p point -1)
	      (character-offset point -1))
	     ((syntax-closed-paren-char-p c)
	      (push c paren-stack)
	      (character-offset point -1)
	      (when (zerop (incf depth))
		(return point)))
	     ((syntax-open-paren-char-p c)
	      (unless (or (and (< 0 depth)
			       (null paren-stack))
			  (syntax-equal-paren-p c (car paren-stack)))
		(return nil))
	      (pop paren-stack)
	      (character-offset point -1)
	      (when (zerop (decf depth))
		(return point)))
	     ((syntax-string-quote-char-p c)
	      (%skip-string-backward point))
	     (t
	      (character-offset point -1))))))

(defun %form-offset-positive (point)
  (skip-space-and-comment-forward point)
  (when (end-buffer-p point)
    (return-from %form-offset-positive nil))
  (syntax-skip-expr-prefix-forward point)
  (skip-chars-forward point #'syntax-expr-prefix-char-p)
  (unless (end-buffer-p point)
    (let ((c (character-at point)))
      (cond ((or (syntax-symbol-char-p c)
                 (syntax-escape-char-p c))
             (%skip-symbol-forward point))
            ((syntax-expr-prefix-char-p c)
             (character-offset point 1))
            ((syntax-open-paren-char-p c)
             (%skip-list-forward point 0))
            ((syntax-closed-paren-char-p c)
             nil)
            ((syntax-string-quote-char-p c)
             (%skip-string-forward point))
            (t
             (character-offset point 1))))))

(defun %form-offset-negative (point)
  (skip-space-and-comment-backward point)
  (when (start-buffer-p point)
    (return-from %form-offset-negative nil))
  (let ((c (character-at point -1)))
    (prog1 (cond ((or (syntax-symbol-char-p c)
                      (syntax-escape-char-p c)
                      (syntax-expr-prefix-char-p c))
                  (%skip-symbol-backward point))
                 ((syntax-closed-paren-char-p c)
                  (%skip-list-backward point 0))
                 ((syntax-open-paren-char-p c)
                  nil)
                 ((syntax-string-quote-char-p c)
                  (%skip-string-backward point))
                 (t
                  (character-offset point -1)))
      (skip-chars-backward point #'syntax-expr-prefix-char-p)
      (syntax-skip-expr-prefix-backward point))))

(defun form-offset (point n)
  (with-point-syntax point
    (with-point ((curr point))
      (when (cond ((plusp n)
                   (dotimes (_ n t)
                     (unless (%form-offset-positive curr)
                       (return nil))))
                  (t
                   (dotimes (_ (- n) t)
                     (unless (%form-offset-negative curr)
                       (return nil)))))
        (move-point point curr)))))

(defun scan-lists (point n depth &optional no-errors)
  (with-point-syntax point
    (with-point ((curr point))
      (when (cond ((plusp n)
                   (dotimes (_ n t)
                     (unless (%skip-list-forward curr depth)
                       (if no-errors
                           (return nil)
                           (scan-error)))))
                  (t
                   (dotimes (_ (- n) t)
                     (unless (%skip-list-backward curr depth)
                       (if no-errors
                           (return nil)
                           (scan-error))))))
        (move-point point curr)))))
