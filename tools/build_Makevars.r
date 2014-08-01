## git2r, R bindings to the libgit2 library.
## Copyright (C) 2013-2014 The git2r contributors
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License, version 2,
## as published by the Free Software Foundation.
##
## git2r is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License along
## with this program; if not, write to the Free Software Foundation, Inc.,
## 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

##' Generate object files in path
##'
##' @param path The path to directory to generate object files from
##' @param exclude Files to exclude
##' @return Character vector with object files
o_files <- function(path, exclude = NULL) {
    files <- sub("c$", "o",
                 sub("src/", "",
                     list.files(path, pattern = "[.]c$", full.names = TRUE)))

    if (!is.null(exclude))
        files <- files[!(files %in% exclude)]
    files
}

##' Generate build objects
##'
##' @param files The object files
##' @param Makevars The Makevars file
##' @return invisible NULL
build_objects <- function(files, Makevars) {
    lapply(names(files), function(obj) {
        cat("OBJECTS.", obj, " =", sep="", file = Makevars)
        len <- length(files[[obj]])
        for (i in seq_len(len)) {
            prefix <- ifelse(all(i > 1, (i %% 3) == 1), "    ", " ")
            postfix <- ifelse(all(i > 1, i < len, (i %% 3) == 0), " \\\n", "")
            cat(prefix, files[[obj]][i], postfix, sep="", file = Makevars)
        }
        cat("\n\n", file = Makevars)
    })

    cat("OBJECTS =", file = Makevars)
    len <- length(names(files))
    for (i in seq_len(len)) {
        prefix <- ifelse(all(i > 1, (i %% 3) == 1), "    ", " ")
        postfix <- ifelse(all(i > 1, i < len, (i %% 3) == 0), " \\\n", "")
        cat(prefix, "$(OBJECTS.", names(files)[i], ")", postfix, sep="", file = Makevars)
    }
    cat("\n", file = Makevars)

    invisible(NULL)
}

##' Build Makevars.in
##'
##' @return invisible NULL
build_Makevars.in <- function() {
    Makevars <- file("src/Makevars.in", "w")
    on.exit(close(Makevars))

    files <- list(libgit2            = o_files("src/libgit2"),
                  libgit2.hash       = o_files("src/libgit2/hash", "libgit2/hash/hash_win32.o"),
                  libgit2.transports = o_files("src/libgit2/transports"),
                  libgit2.unix       = o_files("src/libgit2/unix"),
                  libgit2.xdiff      = o_files("src/libgit2/xdiff"),
                  http_parser        = o_files("src/http-parser"),
                  root               = o_files("src"))

    cat("# Generated by tools/build_Makevars.r: do not edit by hand\n", file=Makevars)
    cat("PKG_CPPFLAGS = @CPPFLAGS@\n", file = Makevars)
    cat("PKG_LIBS = @LIBS@\n", file = Makevars)
    cat("PKG_CFLAGS = -Ilibgit2 -Ilibgit2/include -Ihttp-parser @GIT2R_HAVE_SSL@ @GIT2R_HAVE_SSH2@\n", file = Makevars)
    cat("\n", file = Makevars)

    build_objects(files, Makevars)

    invisible(NULL)
}

##' Build Makevars.in
##'
##' @return invisible NULL
build_Makevars.win <- function() {
    Makevars <- file("src/Makevars.win", "w")
    on.exit(close(Makevars))

    files <- list(libgit2            = o_files("src/libgit2"),
                  libgit2.hash       = o_files("src/libgit2/hash", "libgit2/hash/hash_win32.o"),
                  libgit2.transports = o_files("src/libgit2/transports"),
                  libgit2.xdiff      = o_files("src/libgit2/xdiff"),
                  libgit2.win32      = o_files("src/libgit2/win32"),
                  http_parser        = o_files("src/http-parser"),
                  regex              = o_files("src/regex", c("regex/regcomp.o", "regex/regexec.o", "regex/regex_internal.o")),
                  root               = o_files("src"))

    cat("# Generated by tools/build_Makevars.r: do not edit by hand\n", file=Makevars)
    cat("ifeq \"$(WIN)\" \"64\"\n", file=Makevars)
    cat("PKG_LIBS = -L./winhttp $(ZLIB_LIBS) -lws2_32 -lwinhttp-x64 -lrpcrt4 -lole32\n", file = Makevars)
    cat("else\n", file = Makevars)
    cat("PKG_LIBS = -L./winhttp $(ZLIB_LIBS) -lws2_32 -lwinhttp -lrpcrt4 -lole32\n", file = Makevars)
    cat("endif\n", file = Makevars)
    cat("PKG_CFLAGS = -I. -Ilibgit2 -Ilibgit2/include -Ihttp-parser -Iwin32 -Iregex \\\n", file=Makevars)
    cat("    -DWIN32 -D_WIN32_WINNT=0x0501 -D__USE_MINGW_ANSI_STDIO=1 -DGIT_WINHTTP\n", file=Makevars)
    cat("\n", file = Makevars)

    build_objects(files, Makevars)

    invisible(NULL)
}

##' Extract .NAME in .Call(.NAME
##'
##' @param files R files to extract .NAME from
##' @return data.frame with columns filename and .NAME
extract_git2r_calls <- function(files) {
    df <- lapply(files, function(filename) {
        ## Read file
        lines <- readLines(file.path("R", filename))

        ## Trim comments
        comments <- gregexpr("#", lines)
        for (i in seq_len(length(comments))) {
            start <- as.integer(comments[[i]])
            if (start[1] > 0) {
                if (start[1] > 1) {
                    lines[i] <- substr(lines[i], 1, start[1])
                } else {
                    lines[i] <- ""
                }
            }
        }

        ## Trim whitespace
        lines <- sub("^\\s*", "", sub("\\s*$", "", lines))

        ## Collapse to one line
        lines <- paste0(lines, collapse=" ")

        ## Find .Call
        pattern <- "[.]Call[[:space:]]*[(][[:space:]]*[.[:alpha:]\"][^\",]*"
        calls <- gregexpr(pattern, lines)
        start <- as.integer(calls[[1]])

        if (start[1] > 0) {
            ## Extract .Call
            len <- attr(calls[[1]], "match.length")
            calls <- substr(rep(lines, length(start)), start, start + len - 1)

            ## Trim .Call to extract .NAME
            pattern <- "[.]Call[[:space:]]*[(][[:space:]]*[\"]?"
            calls <- sub(pattern, "", calls)
            return(data.frame(filename = filename,
                              .NAME = calls,
                              stringsAsFactors = FALSE))
        }

        return(NULL)
    })

    df <- do.call("rbind", df)
    df[order(df$filename),]
}

##' Check that .NAME in .Call(.NAME is prefixed with 'git2r_'
##'
##' Raise an error in case of missing 'git2r_' prefix
##' @param calls data.frame with the name of the C function to call
##' @return invisible NULL
check_git2r_prefix <- function(calls) {
    .NAME <- grep("git2r_", calls$.NAME, value=TRUE, invert=TRUE)

    if (!identical(length(.NAME), 0L)) {
        i <- which(calls$.NAME == .NAME)
        msg <- sprintf("%s in %s\n", calls$.NAME[i], calls$filename[i])
        msg <- c("\n\nMissing 'git2r_' prefix:\n", msg, "\n")
        stop(msg)
    }

    invisible(NULL)
}

## Check that all git2r C functions are prefixed with 'git2r_'
calls <- extract_git2r_calls(list.files("R", "*.r"))
check_git2r_prefix(calls)

## Generate Makevars
build_Makevars.in()
build_Makevars.win()
