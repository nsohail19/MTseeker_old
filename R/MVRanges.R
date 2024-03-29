#' like a VRanges, but for mitochondria
#' 
#' @import VariantAnnotation
#' 
#' @exportClass MVRanges
setClass("MVRanges", 
         representation(coverage="numeric"),
         contains="VRanges")


#' wrap a VRanges for mitochondrial use
#'
#' @param   vr        the VRanges
#' @param   coverage  estimated coverage
#'
#' @return            an MVRanges
#' 
#' @export
MVRanges <- function(vr, coverage) new("MVRanges", vr, coverage=coverage)


#' MVRanges methods (centralized).
#'
#' Many of these methods can be dispatched from an MVRangesList OR an MVRanges.
#' In such cases, the method will usually, but not always, be apply()ed. 
#' 
#' @section Utility methods:
#' 
#' `pos` returns a character vector describing variant positions. 
#' `filt` returns a subset of variant calls where PASS == TRUE (i.e. filtered)
#' `coverage` returns the estimated average mitochondrial read coverage depth
#'
#' @section Annotation methods:
#' 
#' `type` returns a character vector describing variant type (SNV or indel)
#' `genes` retrieves a GRanges of mitochondrial gene locations for an MVRanges
#' `snpCall` retrieves single nucleotide variant polymorphisms PASSing filters
#' `annotation` gets (perhaps oddly) an MVRanges object annotated against rCRS
#' `getAnnotations` returns the GRanges of gene/region annotations for an MVR
#' `encoding` returns variants residing in coding regions (consequence unknown)
#' `locateVariants` annotates variants w/region, gene, and localStart/localEnd
#' `predictCoding` returns variants consequence predictions as one might expect
#' `tallyVariants` returns a named vector of variant types by annotated region.
#' `summarizeVariants` uses MitImpact to attempt annotation of coding variants.
#'
#' @param x             an MVRanges
#' @param object        an MVRanges
#' @param annotations   an MVRanges
#' @param query         an MVRanges
#' @param filterLowQual boolean; drop non-PASSing variants from locateVariants?
#'
#' @aliases locateVariants getAnnotations predictCoding genes
#' @aliases snpCall annotation tallyVariants summarizeVariants
#' 
#' @name                MVRanges-methods
NULL


#' @rdname    MVRanges-methods
#' @export
setMethod("coverage", signature(x="MVRanges"), function(x) x@coverage)


#' @rdname    MVRanges-methods
#' @export
setMethod("type", signature(x="MVRanges"), 
          function(x) ifelse(nchar(ref(x)) == nchar(alt(x)), "SNV", "indel"))


#' @rdname    MVRanges-methods
#' @export
setMethod("genes", signature(x="MVRanges"), 
          function(x) subset(getAnnotations(x), region == "coding"))


#' @rdname    MVRanges-methods
#' @export
setMethod("snpCall", signature(object="MVRanges"),
          function(object) subset(object, nchar(alt) == nchar(ref)))


#' @rdname    MVRanges-methods
#' @export
setMethod("pos", signature(x="MVRanges"), 
          function(x) {
            sapply(apply(cbind(start(x),end(x)),1, unique), paste, collapse="-")
          })


#' @rdname    MVRanges-methods
#' @export
setMethod("show", signature(object="MVRanges"),
          function(object) {
            callNextMethod()
            cat(paste0("  genome: ", genome(object)))
            if ("annotation" %in% names(metadata(object))) {
              cat(" (try getAnnotations(object))")
            }
            cat(paste0(", ~", round(coverage(object)), "x read coverage")) 
            cat("\n")
          })


#' @rdname    MVRanges-methods
#' @export
setMethod("annotation", signature(object="MVRanges"), 
          function(object) {

            if (!"annotation" %in% names(metadata(object))) {
              data(mtAnno.rCRS)
              metadata(object)$annotation <- mtAnno
            }

            anno <- getAnnotations(object)
            ol <- findOverlaps(object, anno)
            object$gene <- NA_character_
            object[queryHits(ol)]$gene <- names(anno)[subjectHits(ol)] 
            object$region <- NA_character_
            object[queryHits(ol)]$region <- anno[subjectHits(ol)]$region
            return(object)

          })

# previously defined in chromvar
setGeneric("getAnnotations",
           function(annotations, ...) standardGeneric("getAnnotations"))

#' @rdname    MVRanges-methods
#' @export
setMethod("getAnnotations", signature(annotations="MVRanges"), 
          function(annotations) {
            if (is.null(metadata(annotations)$annotation)) {
              data(mtAnno.rCRS)
              return(mtAnno)
            } else { 
              return(metadata(annotations)$annotation)
            }
          })


#' @rdname    MVRanges-methods
#' @export
setMethod("encoding", signature(x="MVRanges"), 
          function(x) {

            # limit the search 
            x <- locateVariants(x) 
            x <- subset(x, region == "coding") 
            chrM <- grep("(MT|chrM|rCRS|RSRS)", seqlevelsInUse(x), value=TRUE)
            return(keepSeqlevels(x, chrM, pruning.mode="coarse"))

          })


#' @rdname    MVRanges-methods
#' @export
setMethod("filt", signature(x="MVRanges"), function(x) subset(x, x$PASS==TRUE))


#' @rdname    MVRanges-methods
#' @export
setMethod("genome", signature(x="MVRanges"), 
          function(x) unique(seqinfo(x)@genome))


#' @rdname    MVRanges-methods
#' @export
setMethod("locateVariants", 
          signature(query="MVRanges","missing","missing"),
          function(query, filterLowQual=FALSE, ...) {

            if (filterLowQual == TRUE) query <- filt(query)
            if ("gene" %in% names(mcols(query)) &
                "region" %in% names(mcols(query)) &
                "localEnd" %in% names(mcols(query)) & 
                "localStart" %in% names(mcols(query)) &
                "startCodon " %in% names(mcols(query)) &
                "endCodon" %in% names(mcols(query))) {
              return(query) # done 
            }

            data("mtAnno.rCRS", package="MTseeker")
            metadata(query)$annotation <- mtAnno

            ol <- findOverlaps(query, mtAnno, ignore.strand=TRUE)
            query$gene <- NA_character_
            query[queryHits(ol)]$gene <- names(mtAnno)[subjectHits(ol)] 
            query$region <- NA_character_
            query[queryHits(ol)]$region <- mtAnno[subjectHits(ol)]$region

            ## Localized genic coordinates
            anno <- subset(mtAnno, region == "coding") 
            ol2 <- findOverlaps(query, anno, ignore.strand=TRUE)
            query$localStart <- NA_integer_
            query[queryHits(ol2)]$localStart <- 
              start(query[queryHits(ol2)]) - start(anno[subjectHits(ol2)])
            query$localEnd <- NA_integer_
            query[queryHits(ol2)]$localEnd <- 
              end(query[queryHits(ol2)]) - start(anno[subjectHits(ol2)])
            
            ## Affected reference codon(s)
            query$startCodon <- NA_integer_
            query[queryHits(ol2)]$startCodon <- 
              query[queryHits(ol2)]$localStart %/% 3
            query$endCodon <- NA_integer_
            query[queryHits(ol2)]$endCodon <- 
              query[queryHits(ol2)]$localEnd %/% 3

            return(query)

          })


#' @rdname    MVRanges-methods
#' @export
setMethod("tallyVariants", signature(x="MVRanges"), 
          function(x, filterLowQual=TRUE, ...) {

            located <- locateVariants(x, filterLowQual=filterLowQual)
            table(located$region)

          })


#' @rdname    MVRanges-methods
#' @export
setMethod("predictCoding", # mitochondrial annotations kept internally
          signature(query="MVRanges", "missing", "missing", "missing"), 
          function(query, ...) injectMtVariants(filt(query)))


#' @rdname    MVRanges-methods
#' @export
setMethod("summarizeVariants", signature(query="MVRanges","missing","missing"),
          function(query, ...) {
          
            # helper function  
            getImpact <- function(pos) {
              url <- paste("http://mitimpact.css-mendel.it", "api", "v2.0",
                           "genomic_position", sub("^(g|m)\\.","",pos), sep="/")
              res <- as.data.frame(read_json(url, simplifyVector=TRUE)$variants)
              if (nrow(res) > 0) {
                res$genomic <- with(res, paste0("m.", Start, Ref, ">", Alt))
                res$protein <- with(res, paste0("p.",AA_ref,AA_position,AA_alt))
                res$change <- with(res, paste(Gene_symbol, protein))
                res[, c("genomic","protein","change","APOGEE_boost_consensus",
                        "MtoolBox","Mitomap_Phenotype","Mitomap_Status",
                        "OXPHOS_complex","dbSNP_150_id","Codon_substitution")]
              } else {
                return(NULL)
              }
            }

            hits <- lapply(pos(encoding(query)), getImpact)
            hits <- hits[which(sapply(hits, length) > 0)] 

            # be precise, if possible
            for (h in names(hits)) {
              j <- hits[[h]]
              if (h %in% j$genomic) hits[[h]] <- j[which(j$genomic == h),]
            }

            do.call(rbind, hits)

          })
