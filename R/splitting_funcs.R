# abstract out interfaces to data splitting backends for split-apply-combine strategy
callGroupedExec <- function(.data, .output, ...)
{
    gvars <- group_vars(.data)
    if(length(gvars) == 0)
        stop("no groups defined")

    fs <- rxGetFileSystem(.data)
    cc <- rxGetComputeContext()

    # must use rxExecBy if data is on HDFS, or compute context is distributed
    outlst <- if(.dxOptions$useExecBy || inherits(fs, "RxHdfsFileSystem") || inherits(cc, "RxHadoopMR"))
        callExecBy(.data, ...)
    else callSplit(.data, ...)

    if(is.character(.output))
        .output <- modifyXdf(.data, file=.output)
    combineGroups(outlst, .output, gvars)
}


callExecBy <- function(.data, .func, ..., .captures=list())
{
    rxver <- packageVersion("RevoScaleR")
    if(rxver < package_version("9.1"))
        stop("rxExecBy not available in this version of RevoScaleR")

    .captures$.composite <- is_composite_xdf(.data)
    .captures$.tblDir <- get_dplyrxdf_dir(rxGetFileSystem(.data))

    enclosFunc <- function(keys, data, .func, ..., .captures)
    {
        e <- list2env(.captures)
        attach(e)
        on.exit(detach())
        .func(data, ...)
    }

    funcParams <- list(.func=.func, ..., .captures=.captures)
    execByResult(unTbl(.data), group_vars(.data), enclosFunc, funcParams)
}


callSplit <- function(.data, .func, ..., .captures=list())
{
    if(in_hdfs(.data))
        stop("cannot use manual splitting for data in HDFS")

    .captures$.composite <- is_composite_xdf(.data)
    .captures$.tblDir <- get_dplyrxdf_dir(rxGetFileSystem(.data))

    # rxExec execObjects doesn't work with object names starting with .
    enclosFunc <- function(data, .func, ..., .captures)
    {
        e <- list2env(.captures)
        attach(e)
        on.exit(detach())
        .func(data, ...)
    }

    xdflst <- splitGroups(.data)
    on.exit(lapply(xdflst, delete_xdf))

    rxExec(enclosFunc, rxElemArg(xdflst), .func, ..., .captures=.captures)
}

