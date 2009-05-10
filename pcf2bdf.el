;;; pcf2bdf.el --- view .pcf compiled font files as bdf

;; Copyright 2008 Kevin Ryde

;; Author: Kevin Ryde <user42@zip.com.au>
;; Version: 1
;; Keywords: data
;; URL: http://www.geocities.com/user42_kevin/pcf2bdf/index.html

;; pcf2bdf.el is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation; either version 3, or (at your option) any later
;; version.
;;
;; pcf2bdf.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
;; Public License for more details.
;;
;; You can get a copy of the GNU General Public License online at
;; <http://www.gnu.org/licenses>.

;;; Commentary:

;; This is a bit of fun running the pcf2bdf program on .pcf font files to
;; see bdf source.  The main aim is to see sizes, comments, copyright
;; notice, etc, but cute use of `format-alist' in fact allows saving, even
;; if you almost certainly won't want to do that.

;;; Install:

;; To make M-x pcf2bdf available, put pcf2bdf.el somewhere in your load-path
;; and the following in your .emacs
;;
;;     (autoload 'pcf2bdf "pcf2bdf" nil t)
;;     (modify-coding-system-alist 'file "\\.pcf\\'" 'raw-text-unix)
;;
;; To use pcf2bdf automatically on pcf files (and this is the suggested
;; usage) also put
;;
;;     (add-to-list 'auto-mode-alist '("\\.pcf\\'" . pcf2bdf))
;;
;; There's autoload tags below for this, if you use `update-file-autoloads'
;; and friends.

;;; History:

;; Version 1 - the first version.

;;; Emacsen:

;; Designed for Emacs 21 and 22, works in XEmacs 21.


;;; Code:

;;;###autoload
(modify-coding-system-alist 'file "\\.pcf\\'" 'raw-text-unix)

;;;###autoload (add-to-list 'auto-mode-alist '("\\.pcf\\'" . pcf2bdf))


;; xemacs incompatibilities
(defalias 'pcf2bdf-make-temp-file
  (if (fboundp 'make-temp-file)
      'make-temp-file   ;; emacs
    ;; xemacs21
    (autoload 'mm-make-temp-file "mm-util") ;; from gnus
    'mm-make-temp-file))
(defalias 'pcf2bdf-set-buffer-multibyte
  (if (fboundp 'set-buffer-multibyte)
      'set-buffer-multibyte  ;; emacs
    'identity))              ;; not applicable in xemacs21


;; Error messages from bdftopcf, eg.
;;     BDF Error on line 3: Blah Blah
;;
;; There's no filename in the messages but a couple of hacks below get
;; around that for the error output buffer.
;;
(eval-after-load "compile"
  '(let ((elem '(pcf2bdf--bdftopcf "^BDF Error on line \\([0-9]+\\)"
                                   nil 1)))

     (cond ((boundp 'compilation-error-regexp-systems-list)
            ;; xemacs21
            (add-to-list 'compilation-error-regexp-alist-alist
                         (list (car elem)
                               '("^\\(BDF Error\\) on line \\([0-9]+\\)" 1 2)))
            (compilation-build-compilation-error-regexp-alist))

           ((boundp 'compilation-error-regexp-alist-alist)
            ;; emacs22
            (add-to-list 'compilation-error-regexp-alist-alist elem)
            (add-to-list 'compilation-error-regexp-alist (car elem)))

           (t
            ;; emacs21
            (add-to-list 'compilation-error-regexp-alist (cdr elem))))))


;; The pattern for automatic detection would be "\\`\x01\x66\x63\x70", but
;; it's conceivable someone could make a pcf mode displaying the glyphs as
;; images, or something like that, in which case auto-decode would be
;; actively harmful.
;;
;; `file' 4.24 /usr/share/file/magic notes there's a potential clash with
;; MIPSEL COFF object file too, which starts with #x01 #x66.  Though that's
;; hardly likely to be a problem in practice.
;;
(add-to-list 'format-alist `(pcf2bdf
                             "PCF compiled font file."
                             nil ;; no automatic decode
                             pcf2bdf-decode
                             pcf2bdf-encode
                             t     ;; encode modifies the region
                             nil)) ;; write removes from buffer-file-formats

(defun pcf2bdf-decode (beg end)
  "Run pcf2bdf on raw .pcf bytes in the current buffer.
This function is for use from `format-alist'.

The buffer should be unibyte as per a `raw-text-unix' read.  The
bytes are put through pcf2bdf to get bdf text and the buffer is
switched to multibyte.  An error is thrown if pcf2bdf can't be
run or the buffer contents are invalid."

  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      ;; pretty sure pcf2bdf spits out ascii-only, but go `undecided'
      (pcf2bdf-run-fmt "pcf2bdf" 'raw-text-unix 'undecided nil)
      (pcf2bdf-set-buffer-multibyte t)
      (point-max))))

(defun pcf2bdf-encode (beg end buffer)
  "Run bdftopcf on bdf text in the current buffer.
This function is for use from `format-alist'.

The buffer text is put through bdftopcf to produce pcf bytes,
which replace the text and the buffer is switched to unibyte.
An error is thrown if bdftopcf can't be run or the buffer
contents are invalid."

  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      ;; dunno what input coding bdftopcf expects, chances are it's meant to
      ;; be all ascii
      (pcf2bdf-run-fmt "bdftopcf" 'iso-8859-1 'raw-text-unix buffer)
      (point-max))))

(defvar pcf2bdf-originating-buffer nil
  "Originating bdf text buffer for *pcf2bdf-errors*.")
(make-variable-buffer-local 'pcf2bdf-originating-buffer)

(defadvice compilation-find-file (around pcf2bdf activate)
  "Use `pcf2bdf-originating-buffer' for bdftopcf errors."
  (if (and (member filename '("*unknown*"   ;; emacs22
                              "bdftopcf"    ;; emacs21 time+file line below
                              "BDF Error")) ;; xemacs21 hack
           pcf2bdf-originating-buffer)
      (setq ad-return-value pcf2bdf-originating-buffer)
    ad-do-it))

(defun pcf2bdf-run-fmt (command write-coding read-coding originating-buffer)
  "Run bdftopcf or pcf2bdf on the current buffer.
COMMAND is a string \"bdftopcf\" or \"pcf2bdf\", the program to
run.  Program output replaces the buffer contents.

ORIGINATING-BUFFER is the source buffer for when running bdftopcf.
This might be different from the current buffer.  It's recorded
as the place to go for errors."

  (let ((errfile (pcf2bdf-make-temp-file "pcf2bdf-el-")))
    (unwind-protect
        (let ((status (let ((coding-system-for-write write-coding)
                            (coding-system-for-read  read-coding))
                        (call-process-region
                         (point-min) (point-max) command
                         t              ;; delete old
                         (list t        ;; stdout here
                               errfile) ;; stderr to file
                         nil            ;; no redisplay
                         ))))

          (unless (eq 0 status)
            (switch-to-buffer "*pcf2bdf-errors*")
            (setq buffer-read-only nil)
            (erase-buffer)

            ;; in emacs21 the first two lines are ignored for errors, so
            ;; stick some padding
            (insert "\n\n")

            ;; insert a dummy filename line for emacs21
            ;; `compilation-file-regexp-alist' to match, otherwise the "BDF
            ;; Error" pattern with no filename provokes an error
            (insert (current-time-string) "  bdftopcf:\n\n")

            (insert-file-contents errfile)
            (goto-char (point-min))
            (if originating-buffer
                (compilation-mode))
            (setq pcf2bdf-originating-buffer originating-buffer)
            (error "%s error, see *pcf2bdf-errors* buffer" command)))

      (delete-file errfile))))

;;;###autoload
(defun pcf2bdf ()
  "Decode a pcf font file to bdf text using the pcf2bdf program.
The buffer should be raw bytes (`raw-text-unix' unibyte).

The `format-alist' mechanism is used, so the bdf can in fact be
edited and re-saved, with recoding done with the usual X bdftopcf
program.  But it's unlikely you'd want to do that since there's
nothing to set the various endianness and width options to
bdftopcf which make a pcf a given server will most enjoy.

With `auto-compression-mode' enabled .pcf.gz files can be read
too, the bytes should be already decompressed when they reach
`pcf2bdf'.

Note if saving that `tar-mode' (as of Emacs 22) doesn't follow
`buffer-file-format' when saving so saving a .pcf inside a .tar
gives just the bdf text.  This afflicts all file format things,
including the builtin `enriched-mode'.  So don't do that.
`archive-mode' saving is ok.

For more on the pcf2bdf program see
    http://www.tsg.ne.jp/GANA/S/pcf2bdf

For more on pcf2bdf.el see
    http://www.geocities.com/user42_kevin/pcf2bdf/index.html"

  (interactive)
  (unless (memq 'pcf2bdf buffer-file-format)
    (let ((buffer-read-only nil))
      (format-decode-buffer 'pcf2bdf)))

  (if (fboundp 'bdf-mode) ;; if a hypothetical bdf-mode exists
      (bdf-mode)
    (fundamental-mode)))

(provide 'pcf2bdf)

;;; pcf2bdf.el ends here
