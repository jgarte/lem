;; -*- Mode: LISP; Package: LEM -*-

(in-package :lem)

(export '(*c-mode-keymap*
          *c-syntax-table*
          c-mode))

(defvar *c-mode-keymap* (make-keymap "c"))

(defvar *c-syntax-table*
  (make-syntax-table
   :space-chars '(#\space #\tab #\newline)
   :symbol-chars '(#\_)
   :paren-alist '((#\( . #\))
                  (#\[ . #\])
                  (#\{ . #\}))
   :string-quote-chars '(#\" #\')
   :escape-chars '(#\\)
   :line-comment-preceding-char #\/
   :line-comment-following-char #\/
   :block-comment-preceding-char #\/
   :block-comment-following-char #\*))

(define-major-mode c-mode nil
  (:name "c"
   :keymap *c-mode-keymap*
   :syntax-table *c-syntax-table*)
  (buffer-put (window-buffer) :enable-syntax-highlight t))

(dolist (str '("void" "char" "short" "int" "long" "float" "double" "auto"
               "static" "const" "signed" "unsigned" "extern" "volatile"
               "register" "return" "goto" "if" "else" "switch" "case"
               "default" "break" "for" "while" "do" "continue" "typedef"
               "struct" "enum" "union" "sizeof" "inline" "restrict"
               "_Bool" "_Complex" "Imaginary" "bool"))
  (syntax-add-keyword *c-syntax-table* str
                      :regex-p nil
                      :word-p t
                      :attr :keyword-attr))

(syntax-add-keyword *c-syntax-table*
                    "^#\\S+"
                    :regex-p t
                    :attr :constant-attr)

(defvar *c-compile-command* "make")

(define-key *c-mode-keymap* (kbd "C-c") 'c-compile)
(define-command c-compile () ()
  (grep-update
   (with-output-to-string (out)
     (shell-command (setq *c-compile-command*
                          (minibuf-read-string "compile command: "
                                               *c-compile-command*))
                    :error-output out))))

(define-key *c-mode-keymap* (kbd "C-M-a") 'c-beginning-of-defun)
(define-command c-beginning-of-defun (n) ("p")
  (beginning-of-defun-abstract n #'(lambda () (looking-at "^{")))
  (prev-line))

(define-key *c-mode-keymap* (kbd "C-M-e") 'c-end-of-defun)
(define-command c-end-of-defun (n) ("p")
  (beginning-of-defun-abstract (- n) #'(lambda () (looking-at "^}")))
  (next-line))

(setq *auto-mode-alist*
      (append '(("\\.c$" . c-mode)
                ("\\.h$" . c-mode))
              *auto-mode-alist*))
