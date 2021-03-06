context("Xdf file utilities in HDFS")

# set the compute context manually

detectHdfsConnection()

mtc <- RxXdfData("mtcars", fileSystem=RxNativeFileSystem(), createCompositeSet=TRUE)


verifyHdfsData <- function(xdf, expectedClass)
{
    isTRUE(xdf@createCompositeSet) && rxHadoopFileExists(xdf@file) && class(xdf) == expectedClass # test for exact class
}

# check actual data -- slow but necessary to check that non-Revo file ops succeeded
verifyCompositeData <- function(xdf, expectedClass)
{
    isTRUE(xdf@createCompositeSet) && is.data.frame(as.data.frame(xdf)) && class(xdf) == expectedClass # test for exact class
}

.path <- function(path)
{
    normalizeHdfsPath(path)
}

test2 <- tempfile(tmpdir="/tmp")
hdfs_dir_create(test2)


test_that("local_exec works",
{
    local_exec(rxDataStep(mtcars, mtc, overwrite=TRUE))
    local_exec(verifyCompositeData(mtc, "RxXdfData"))
})

test_that("copy_to works",
{
    if(hdfs_dir_exists("mtcars"))
        hdfs_dir_remove("mtcars")
    if(hdfs_dir_exists("mtc"))
        hdfs_dir_remove("mtc")
    out <- copy_to_hdfs(mtcars)
    expect_true(hdfs_dir_exists("mtcars"))
    expect_true(verifyCompositeData(out, "RxXdfData"))
    hdfs_dir_remove("mtcars")

    out <- copy_to_hdfs(mtc)
    expect_true(hdfs_dir_exists("mtcars"))
    expect_true(verifyCompositeData(out, "RxXdfData"))
    hdfs_dir_remove("mtcars")

    out <- copy_to_hdfs(mtc, "mtc")
    expect_true(hdfs_dir_exists("mtc"))
    expect_true(verifyCompositeData(out, "RxXdfData"))
    hdfs_dir_remove("mtc")

    if(hdfs_dir_exists("testdir"))
        hdfs_dir_remove("testdir")
    hdfs_dir_create("testdir")
    out <- copy_to_hdfs(mtcars, "testdir")
    expect_true(hdfs_dir_exists("testdir/mtcars"))
    expect_true(verifyCompositeData(out, "RxXdfData"))
    hdfs_dir_remove("testdir/mtcars")

    out <- copy_to_hdfs(mtcars, "testdir/mtc")
    expect_true(hdfs_dir_exists("testdir/mtc"))
    expect_true(verifyCompositeData(out, "RxXdfData"))
    hdfs_dir_remove("testdir/mtc")
    hdfs_dir_remove("testdir")
})

mthc <- copy_to_hdfs(mtcars)

test_that("rename works",
{
    tbl <- rename_xdf(mthc, "mthc2")
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    expect_false(hdfs_dir_exists(mthc@file))

    rename_xdf(tbl, "mtcars")
    expect_true(verifyCompositeData(mthc, "RxXdfData"))
    expect_false(hdfs_dir_exists(tbl@file))

    expect_error(rename(mthc, file.path(test2, "foo")))
})

test_that("copy and move work",
{
    # copy to same dir = working dir
    tbl <- copy_xdf(mthc, "test53")
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    expect_identical(.path(tbl@file), .path("test53"))

    # move to same dir = working dir (rename)
    tbl2 <- move_xdf(tbl, "test53a")
    expect_true(verifyCompositeData(tbl2, "RxXdfData"))
    expect_false(hdfs_dir_exists(tbl@file))
    expect_identical(.path(tbl2@file), .path("test53a"))

    # copy to different dir
    tbl <- copy_xdf(mthc, test2)
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    expect_identical(.path(tbl@file), .path(file.path(test2, "mtcars")))

    # move to different dir
    tbl2 <- move_xdf(tbl2, test2)
    expect_true(verifyCompositeData(tbl2, "RxXdfData"))
    expect_identical(.path(tbl2@file), .path(file.path(test2, "test53a")))

    # copy to same explicit dir
    dest <- .path("test53")
    if(hdfs_dir_exists(dest))
        hdfs_dir_remove(dest)
    tbl <- copy_xdf(mthc, dest)
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    expect_identical(.path(tbl@file), dest)

    # move to same explicit dir
    dest2 <- .path("test53a")
    if(hdfs_dir_exists(dest2))
        hdfs_dir_remove(dest2)
    tbl2 <- move_xdf(tbl, dest2)
    expect_true(verifyCompositeData(tbl2, "RxXdfData"))
    expect_false(hdfs_dir_exists(tbl@file))
    expect_identical(.path(tbl2@file), dest2)

    # copy to different dir + rename
    dest <- .path(file.path(test2, "test53"))
    if(hdfs_dir_exists(dest))
        hdfs_dir_remove(dest)
    tbl <- copy_xdf(mthc, dest)
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    expect_identical(.path(tbl@file), dest)

    # move to different dir + rename
    dest2 <- .path(file.path(test2, "test53a"))
    if(hdfs_dir_exists(dest2))
        hdfs_dir_remove(dest2)
    tbl2 <- move_xdf(mthc, dest2)
    expect_true(verifyCompositeData(tbl2, "RxXdfData"))
    expect_false(hdfs_dir_exists(mthc@file))
    expect_identical(.path(tbl2@file), dest2)

    # recreate original file
    copy_to_hdfs(mtc, name="mtcars")
})

test_that("persist works",
{
    expect_warning(persist(mthc, "test53"))
    tbl <- as(mthc, "tbl_xdf") %>% persist("test53", move=FALSE)
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
    tbl2 <- as(tbl, "tbl_xdf") %>% persist("test53a", move=TRUE)
    expect_true(verifyCompositeData(tbl2, "RxXdfData"))
    expect_false(hdfs_dir_exists(tbl@file))

    expect_warning(tbl <- as(mthc, "tbl_xdf") %>% persist("test53.xdf", composite=FALSE, move=FALSE))
    expect_true(verifyCompositeData(tbl, "RxXdfData"))
})

test_that("collect and compute work",
{
    tbl <- collect(mthc)
    expect_true(is.data.frame(tbl))
    tbl <- compute(mthc)
    expect_true(local_exec(verifyCompositeData(tbl, "tbl_xdf")))
    tbl <- compute(mthc, as_data_frame=TRUE)
    expect_true(is.data.frame(tbl))
})


hdfs_dir_remove(c("mtcars", "test53", "test53a", test2), skipTrash=TRUE)
unlink("mtcars", recursive=TRUE)

