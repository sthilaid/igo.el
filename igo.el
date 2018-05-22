
(define-error 'igo-error-sgf-parsing "sgf parsing error occured...")

(setq igo-examble-game (let ((ex-game-file "ff4_ex.sgf"))
                         (if (file-exists-p ex-game-file)
                             (with-temp-buffer
                               (insert-file-contents ex-game-file)
                               (buffer-string))
                           "")))

(defun igo-parse-ignore-char (c)
  (or (= c ?\n)
      (= c ?\v)
      (= c ?\s)
      (= c ?\t)
      (= c ?\r)
      (= c ?\f)))

(cl-loop for c across "(allo)"
         for i from 0 to (length "(allo)")
         collect (cons c i))

(defun igo-parse-next-token (str token)
  (if (> (length token) 0)
      (let ((token-idx 0))
        (cl-loop for c across str
                 for i from 0 to (length str)

                 if (and (not (igo-parse-ignore-char c))
                         (not (= c (elt token token-idx))))
                 do (signal 'igo-error-sgf-parsing (concat "wrong token, expecting: " token " got: " str))

                 if (and (not (igo-parse-ignore-char c))
                         (= c (elt token token-idx)))
                 do (setq token-idx (+ token-idx 1))

                 if (>= token-idx (length token))
                 return (substring str (+ i 1))))
    (signal 'igo-error-sgf-parsing (concat "wrong token, expecting: " token " got: " str))))

;;(igo-parse-next-token "   \n\r(allo)" "(")
;; (igo-parse-next-token "aaa)" "aab")

(defun igo-parse-sgf-list (sgf-str parsing-function)
  (labels ((parse-list (acc str) (let ((element (funcall parsing-function str)))
                                       (if element
                                           (parse-list (cons (car element) acc) (cdr element))
                                         (cons acc str)))))
    (parse-list '() sgf-str)))

(defun igo-parse-is-letter? (char)
  (let ((downcase-char (downcase char)))
    (and (>= downcase-char ?a)
         (<= downcase-char ?z))))

;; (igo-parse-is-letter? (elt "aaa" 0))
;; (igo-parse-is-letter? ?a)

(defun igo-parse-sgf-property-id (sgf-str)
  (labels ((call-error () (signal 'igo-error-sgf-parsing (concat "invalid property for " sgf-str)))
           (parse-proptery (acc str)
                           (if (string= str "")
                               (cons acc str)
                             (let ((char (elt str 0)))
                               (if (igo-parse-is-letter? char)
                                   (parse-proptery (concat acc (list char)) (substring str 1))
                                 (if (string= acc "")
                                     (if (igo-parse-ignore-char char)
                                         (parse-proptery acc (substring str 1))
                                       (call-error))
                                   (cons acc str)))))))
    (parse-proptery "" sgf-str)))

(igo-parse-sgf-property-id "aaa")
(igo-parse-sgf-property-id "   \raaa[")
(igo-parse-sgf-property-id "   \raBaZ  [")

;; None | Number | Real | Double | Color | SimpleText |
;; Text | Point  | Move | Stone
;;      UcLetter   = "A".."Z"
;;      Digit      = "0".."9"
;;      None       = ""
        
;;      Number     = [("+"|"-")] Digit { Digit }
;;      Real       = Number ["." Digit { Digit }]
        
;;      Double     = ("1" | "2")
;;      Color      = ("B" | "W")
        
;;      SimpleText = { any character (handling see below) }
;;      Text       = { any character (handling see below) }
        
;;      Point      = game-specific
;;      Move       = game-specific
;;      Stone      = game-specific
(defun igo-parse-sgf-value-type (sgf-str)
  (labels ((parse-double (str) (if (and (>= (length str) 2)
                                        (let ((char (elt str 0))) (or (= char ?1) (= char ?2)))
                                        (= (elt str 1) ?\]))
                                   (cons (list 'double (elt str 0)) (substring str 1))
                                 nil))
           (parse-color (str) (if (and (>= (length str) 2)
                                        (let ((char (elt str 0))) (or (= char ?B) (= char ?W)))
                                        (= (elt str 1) ?\]))
                                   (cons (list 'color (elt str 0)) (substring str 1))
                                 nil))
           (parse-point (str) nil) ; todo
           (parse-move (str) nil) ; todo
           (parse-stone (str) nil) ; todo
           (parse-number (acc str has-decimal?)
                         (let ((char (elt str 0)))
                           (cond ((or (and (string= acc "")
                                           (or (= char ?+)
                                               (= char ?-)))
                                      (and (>= char ?0)
                                           (<= char ?9)))
                                  (parse-number (concat acc (list char)) (substring str 1) nil))

                                 ((and (not has-decimal?) (= char ?.))
                                  (parse-number (concat acc (list char)) (substring str 1) t))

                                 ((= char ?\])
                                  (cons (list 'number acc) str))

                                 (t nil))))
           (parse-text (acc str)
                       (let ((char (elt str 0)))
                         (if (= char ?\])
                             (cons (list 'text acc) str)
                           (parse-text (concat acc (list char)) (substring str 1))))))
    (or (parse-double sgf-str)
               (parse-color sgf-str)
               (parse-point sgf-str)
               (parse-move sgf-str)
               (parse-stone sgf-str)
               (parse-number "" sgf-str nil)
               (parse-text "" sgf-str))))

(igo-parse-sgf-value-type "1]")
(igo-parse-sgf-value-type "B]")
(igo-parse-sgf-value-type "BB]")
(igo-parse-sgf-value-type "+12.33322]")
(igo-parse-sgf-value-type "+12.+33322]")
(igo-parse-sgf-value-type "+12.33.322]") ;; need to fix this
(igo-parse-sgf-value-type "bla blua\r]")

(defun igo-parse-sgf-property-value (sgf-str)
  (igo-parse-next-token sgf-str "[")
  (let ((value-type (igo-parse-sgf-value-type sgf-str)))
    (igo-parse-next-token sgf-str "]")
    value-type))

(defun igo-parse-sgf-property (sgf-str)
  (let* ((property-id (igo-parse-sgf-property-id sgf-str))
         (property-values (igo-parse-sgf-list (cdr property-id) igo-parse-sgf-property-value)))
    (cons (list property-id (car property-values)) (cdr property-values))))

(defun igo-parse-sgf-node (sgf-str)
  (let ((node-str-rest (igo-parse-next-token sgf-str ";")))
    (if node-str-rest
        (igo-parse-sgf-property node-str-rest)
      (signal 'igo-error-sgf-parsing (concat "while paring node: " sgf-str)))))

(igo-parse-sgf-node "test")

;; need have error/exception management!

(defun igo-parse-sgf-sequence (sgf-str)
  (igo-parse-sgf-list sgf-str 'igo-parse-sgf-node))

(defun igo-parse-sgf-gametree (str)
  (let ((seq-str (igo-parse-next-token str "(")))
    (if (not seq-str)
        (signal 'igo-error-sgf-parsing (concat "invalid gametree token ( for: " str))
      (let ((sequence (igo-parse-sgf-sequence seq-str)))
        (progn
          (let ((subtrees (igo-parse-sgf-list (cdr sequence) 'igo-parse-sgf-gametree)))
            (let ((rest (igo-parse-next-token (cdr subtrees) ")")))
              (if (not rest)
                  (signal 'igo-error-sgf-parsing (concat "invalid gametree token ) for: " (cdr subtrees)))
                (cons (list 'gametree (car sequence) (car subtrees))
                      rest)))))))))

(pp (igo-parse-sgf-gametree "   (aaa   (  aaa (aaa)  )\n)"))
(pp (igo-parse-sgf-gametree "(;aaa)"))
(pp (igo-parse-sgf-gametree "(aaa(aaa))"))

(defun igo-parse-sgf-collection (sgf-str)

  )

(defun igo-sgf-parsing (sgf-data)
  "Converts sgf game into internal igo-mode format."
  'todo)

(defvar igo-mode-map
  (let ((map (make-sparse-keymap)))
	;; (define-key map (kbd "<C-M-backspace>") 'ide-grep-solution)
	;; (define-key map (kbd "<C-M-return>") 'ide-grep-project)

	;; (define-key map (kbd "C-M-'") 'ide-find-file)
	;; (define-key map (kbd "M-o") 'ide-find-other-file)
	;; (define-key map (kbd "C-M-o") 'ide-find-and-create-other-file)

	;; (define-key map (kbd "<f7>")	'ide-quick-compile)
	;; (define-key map (kbd "M-<f7>")	'ide-compile-solution)
	;; (define-key map (kbd "C-<f7>")	'ide-compile-project)

	map)
  "igo-mode keymap.")

(define-minor-mode igo-mode
  "ide mode. Provides a convenient way to search for files in large projects defined in different format (.ide or text). Also support compiling projects, to a certain extent."
  :init-value nil
  :global f
  :lighter " igo"
  :keymap 'igo-mode-map
  (let ((igo-buffer (get-buffer-create "*igo*")))
    (switch-to-buffer igo-buffer)
    (setq buffer-read-only 't)))

(provide 'igo)
