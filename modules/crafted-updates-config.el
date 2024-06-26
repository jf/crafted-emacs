;;; crafted-updates-config.el --- Provides automatic update behavior for the configuration.  -*- lexical-binding: t; -*-

;; Copyright (C) 2023
;; SPDX-License-Identifier: MIT

;; Author: System Crafters Community

;;; Commentary:

;; Checks for updates to the Crafted Emacs project.  Provides a
;; function to show the updates before pulling changes.

;; This uses `crafted-emacs-home', which is set on load if it hasn't been
;; set by the user or by `crafted-init-config'. It expects that directory
;; to be a git directory that can be used to checking on updates from
;; upstream.  Defensively would still need to check if that location
;; is `bound-and-true-p' before doing anything.

;;; Code:

;;; Find where Crafted Emacs is located
(unless (boundp 'crafted-emacs-home)
  (setq crafted-emacs-home (project-root (project-current nil (file-name-directory (buffer-file-name)))))
  (warn (format "crafted-emacs-home is not set.  Attempting to use %s" crafted-emacs-home)))

(autoload 'vc-git--out-ok "vc-git")

;;; Public interface

;;;; Commands
(defun crafted-updates-check-for-latest ()
  "Fetches the latest Crafted Emacs.

Get commits from GitHub and notify you if there are any updates."
  (interactive)
  (message "Checking for Crafted Emacs updates...")
  (when (crafted-updates--call-git #' "fetch" "origin")
    (crafted-updates--notify-of-updates)))

(defun crafted-updates-show-latest ()
  "Get latest Crafted Emacs commits.

Shows a buffer containing a log of the latest commits to
Crafted Emacs."
  (interactive)
  (message "Fetching latest commit log for Crafted Emacs...")
  (with-current-buffer (find-file-noselect (expand-file-name
                                            "README.org"
                                            crafted-emacs-home))
    (vc-log-incoming)))

(defun crafted-updates-pull-latest (do-pull)
  "Pull the latest Crafted Emacs version into the local repository.

If DO-PULL is nil then only the latest updates will be shown,
otherwise the local repository will get updated to the GitHub
version.

Interactively, the default if you just type RET is to show recent
changes as if you called `crafted-updates-show-latest'.

With a `\\[universal-argument]' prefix immediately pull changes
and don't prompt for confirmation."
  (interactive
   (list
    (or current-prefix-arg
        (pcase (completing-read "Crafted Update Action: " '("Show Log" "Update") nil t nil nil "Show Log")
          ("Show Log" nil)
          ("Update" t)))))
  (if do-pull
      (crafted-updates--pull-commits)
    (crafted-updates-show-latest)))

;;;; Functions

(defun crafted-updates-status-message ()
  "Status message indicating availble updates or not."
  (let ((commit-count (crafted-updates--get-new-commit-count)))
    (cond ((> commit-count 0) "Crafted Emacs updates are available!")
          ((= commit-count 0) "Crafted Emacs is up to date!")
          ((< commit-count 0) "Current branch is local only!"))))

;;; Customization options - See `M-x customize-group RET crafted-updates'
(defgroup crafted-updates '()
  "Configuration for keeping Crafted Emacs up-to-date."
  :tag "Crafted Updates"
  :group 'crafted)

;; TODO: use a derived type to check that the value is something `run-at-time'
;; will accept
(defcustom crafted-updates-fetch-interval "24 hours"
  "The interval at which `crafted-updates-mode' will check for updates.

The interval is scheduled with `run-at-time', so the value of
this variable must conform to a format accepted by
`run-at-time'."
  :group 'crafted-updates)

;;; Private interface
;; These functions are not intended to be called directly.

(defun crafted-updates--call-git (&rest args)
  "Call git with ARGS."
  (let ((default-directory crafted-emacs-home))
    (with-temp-buffer
      (if (apply #'vc-git--out-ok args)
          (buffer-string)
        nil))))

(defun crafted-updates--pull-commits ()
  "Pull commits from Crafted Emacs repo."
  (message "Pulling latest commits to Crafted Emacs...")
  (with-current-buffer (find-file-noselect
                        (expand-file-name "README.org"
                                          crafted-emacs-home))
    (vc-pull)))

(defun crafted-updates--get-new-commit-count ()
  "Count new commits.

These are commits not currently pulled from the main repo."
  (with-temp-buffer
    (let* ((default-directory crafted-emacs-home)
           (current-branch (car (vc-git-branches)))
           (rev-list-path (concat current-branch "..origin/" current-branch))
           (compare-remote (concat "origin/" current-branch)))
      (if (member compare-remote (split-string (crafted-updates--call-git "branch" "-r")))
          (string-to-number (crafted-updates--call-git "rev-list" "--count" rev-list-path))
        -1))))

(defun crafted-updates--notify-of-updates ()
  "Show a message in *Message* buffer."
  (message (crafted-updates-status-message)))

(defun crafted-updates--poll-git-fetch-status (process)
  "Check to see if the git PROCESS has completed."
  (if (eql (process-status process) 'exit)
      (when (eql (process-exit-status process) 0)
        (message "crafted-updates: git fetch status completed successfully"))
    (run-at-time 1 nil #'crafted-updates--poll-git-fetch-status process)))


(defun crafted-updates--schedule-fetch ()
  "Schedule pulling Crafted Emacs updates."
  (run-at-time crafted-updates-fetch-interval nil #'crafted-updates--do-automatic-fetch))

;;; Minor mode
(define-minor-mode crafted-updates-mode
  "Crafted Emacs updates minor mode.

Provides an automatic update checking feature for Crafted
Emacs.  When enabled, it will automatically check for updates at
the specified `crafted-updates-fetch-interval'."
  :global t
  :group 'crafted-updates
  (when crafted-updates-mode
    (crafted-updates--schedule-fetch)))

(defun crafted-updates--do-automatic-fetch ()
  "Automatically fetch Crafted Emacs updates.

Only runs when `crafted-updates-mode' is active."
  (when crafted-updates-mode
    (crafted-updates-check-for-latest)
    (crafted-updates--schedule-fetch)))

;;; _

(provide 'crafted-updates-config)
;;; crafted-updates-config.el ends here
