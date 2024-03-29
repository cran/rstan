# This file is part of RStan
# Copyright (C) 2012, 2013, 2014, 2015, 2016, 2017 Trustees of Columbia University
# Copyright (C) 2005-2010 Oleg Sklyar
#
# RStan is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# RStan is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

cxxfun_from_dll <- function(sig, code, DLL, check_dll = TRUE) {
  # Create function objects from dll (most of the code are copied from
  # cxxfunction in package inline).
  #
  # Args:
  #  sig: a list of function signatures
  #  DLL: object of class "DLLInfo"
  #  check_dll: check if the dll is loaded: When it is not
  #    loaded, the function call might result in a segfault.

  f <- DLL[['name']]
  if (check_dll) {
    dlls <- getLoadedDLLs()
    if (!f %in% names(dlls))
      stop(paste("dso ", DLL[['path']], " is not loaded", sep = ''))
  }

  res <- vector("list", length(sig))
  names(res) <- names(sig)
  res <- new("CFuncList", res)

  for(i in seq_along(sig)) {
    res[[i]] <- new("CFunc", code = code)
    fn <- function(arg) { NULL }

    ## Modify the function formals to give the right argument list
    args <- formals(fn)[rep(1, length(sig[[i]]))]
    names(args) <- names(sig[[i]])
    formals(fn) <- args

    ## create .Call function call that will be added to 'fn'
    body <- quote(CALL_PLACEHOLDER(EXTERNALNAME, ARG))[c(1:2, rep(3, length(sig[[i]])))]
    for (j in seq_along(sig[[i]])) body[[j + 2]] <- as.name(names(sig[[i]])[j])

    body[[1L]] <- .Call
    body[[2L]] <- getNativeSymbolInfo(names(sig)[[i]], DLL)$address
    ## update the body of 'fn'
    body(fn) <- body
    ## set fn as THE function in CFunc of res[[i]]
    res[[i]]@.Data <- fn
  }
  ## clear the environment
  rm(j)
  convention <- ".Call"
  if (identical(length(sig), 1L)) res[[1L]] else res
}

cxxfun_from_dso_bin <- function(dso) {
  # Create function objects from dll (most of the code are copied from
  # cxxfunction in package inline).
  #
  # Args:
  #  dso: object of class cxxdso
  #
  # Note: we are assuming that the dso is not loaded so
  #   we create the dso file from the raw vector
  #   and then loaded the dso. .

  sig <- dso@sig
  code <- dso@.CXXDSOMISC$cxxfun@code
  tfile <- tempfile()
  f <- basename(tfile)
  libLFile <- paste(tfile, ".", filename_ext(dso@.CXXDSOMISC$dso_last_path), sep = '')
  # write the raw vector containing the dso file to temporary file
  writeBin(dso@.CXXDSOMISC$dso_bin, libLFile)
  cleanup <- function(env) {
    if (file.exists(libLFile) && f %in% names(getLoadedDLLs()))
      dyn.unload(libLFile)
    unlink(libLFile)
  }
#  reg.finalizer(environment(), cleanup, onexit = FALSE)
  DLL <- dyn.load(libLFile)
  assign('dso_last_path', libLFile, dso@.CXXDSOMISC)
  res <- vector("list", length(sig))
  names(res) <- names(sig)
  res <- new("CFuncList", res)
  for(i in seq_along(sig)) {
    res[[i]] <- new("CFunc", code = code)
    fn <- function(arg) { NULL }

    ## Modify the function formals to give the right argument list
    args <- formals(fn)[rep(1, length(sig[[i]]))]
    names(args) <- names(sig[[i]])
    formals(fn) <- args

    ## create .Call function call that will be added to 'fn'
    body <- quote(CALL_PLACEHOLDER(EXTERNALNAME, ARG))[c(1:2, rep(3, length(sig[[i]])))]
    for (j in seq_along(sig[[i]])) body[[j + 2]] <- as.name(names(sig[[i]])[j])

    body[[1L]] <- .Call
    body[[2L]] <- getNativeSymbolInfo(names(sig)[[i]], DLL)$address
    ## update the body of 'fn'
    body(fn) <- body
    ## set fn as THE function in CFunc of res[[i]]
    res[[i]]@.Data <- fn
  }
  ## clear the environment
  rm(j)
  rm(tfile)
  convention <- ".Call"
  if (identical(length(sig), 1L)) res[[1L]] else res
}


dso_path <- function(fx) {
  # find the path for the dynamic shared objects associated with
  # the returned object from cxxfunction
  #
  # Args:
  #   fx: returned object from cxxfunction in package inline
  dllinfo <- getDynLib(fx)
  dllinfo[['path']]
}

read_dso <- function(path) {
  n <- file.info(path)$size
  readBin(path, what = 'raw', n = n)
}

cxxfunctionplus <- function(sig = character(), body = character(),
                            plugin = "default", includes = "",
                            settings = getPlugin(plugin),
                            save_dso = FALSE, module_name = "MODULE",
                            ..., verbose = FALSE) {
  R_version <- with(R.version, paste(major, minor, sep = "."))
  WINDOWS <- .Platform$OS.type == "windows"
  if (WINDOWS && R.version$major < 4) {
    stop("cxxfunctionplus requires R >= 4.0 on Windows to use C++17")
  } else {
    has_USE_CXX17 <- Sys.getenv("USE_CXX17") != ""
    Sys.setenv(USE_CXX17 = 1)
    if (!has_USE_CXX17) on.exit(Sys.unsetenv("USE_CXX17"))
  }
  if (rstan_options("required"))
    pkgbuild::has_build_tools(debug = FALSE) ||
    pkgbuild::has_build_tools(debug = TRUE)

  # compiling with -march=native on windows can cause segfaults
  if (WINDOWS) {
    has_march = .warn_march_makevars()
    if (has_march) {
      user_makevar = Sys.getenv("R_MAKEVARS_USER")
      Sys.setenv(R_MAKEVARS_USER = NULL)
      on.exit(Sys.setenv(R_MAKEVARS_USER = user_makevar))
    }
  }
  if (!isTRUE(verbose)) {
    tf <- tempfile(fileext = ".warn")
    zz <- file(tf, open = "wt")
    sink(zz, type = "output")
    on.exit(close(zz), add = TRUE)
    on.exit(sink(type = "output"), add = TRUE)
  }
  fx <- pkgbuild::with_build_tools(
    cxxfunction(sig = sig, body = body, plugin = plugin, includes = includes,
                settings = settings, ..., verbose = verbose),
    required = rstan_options("required") &&
    # workaround for packages with src/install.libs.R
      !identical(Sys.getenv("WINDOWS"), "TRUE") &&
      !identical(Sys.getenv("R_PACKAGE_SOURCE"), "") )
  if (!isTRUE(verbose)) {
    sink(type = "output")
    close(zz)
    try(file.remove(tf), silent = TRUE)
    on.exit(NULL)
  }
  dso_last_path <- dso_path(fx)
  if (grepl("^darwin", R.version$os) && grepl("clang", get_CXX(FALSE))) {
    CLANG_DIR = tail(n = 1, grep("clang[456789]", value = TRUE,
                                 x = list.dirs("/usr/local", recursive = FALSE)))
    Rv <- R.version
    GOOD <- file.path("/Library", "Frameworks", "R.framework", "Versions",
                      paste(Rv$major, substr(Rv$minor, 1, 1), sep = "."),
                      "Resources", "lib", "libc++.1.dylib")
    if (length(CLANG_DIR) == 1L && file.exists(GOOD)) {
      cmd <- paste("install_name_tool", "-change", CLANG_DIR, GOOD, dso_last_path)
      system(cmd)
      dyn.unload(dso_last_path)
      dyn.load(dso_last_path)
    }
  }
  dso_bin <- if (save_dso) read_dso(dso_last_path) else raw(0)
  dso_filename <- sub("\\.[^.]*$", "", basename(dso_last_path))
  if (!is.list(sig))  {
    sig <- list(sig)
    names(sig) <- dso_filename
  }
  cxxflags <- try(get_makefile_flags("CXXFLAGS"))
  if (!is.character(cxxflags)) cxxflags <- NA_character_
  dso <- new('cxxdso', sig = sig, dso_saved = save_dso,
             dso_filename = dso_filename,
             modulename = module_name,
             system = R.version$system,
             cxxflags = cxxflags,
             .CXXDSOMISC = new.env(parent = emptyenv()))
  assign("cxxfun", fx, envir = dso@.CXXDSOMISC)
  assign("dso_last_path", dso_last_path, envir = dso@.CXXDSOMISC)
  assign("dso_bin", dso_bin, envir = dso@.CXXDSOMISC)
  if (!is.null(module_name) && module_name != '')
    assign("module", Module(module_name, getDynLib(fx)), envir = dso@.CXXDSOMISC)
  return(dso)
}
