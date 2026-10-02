# Terminology

Plant material and sequencing units, from field to reads. Code, docs and the paper use these words in these senses only.

| term | meaning |
|---|---|
| **bulk** | the seed of one BC2S3 NIL (~1 kg), mixed from the ears of its self; one bulk per NIL |
| **plot** | one sowing from a bulk; a NIL can be planted in several plots |
| **sample** | leaf punches of 6 plants (one per plant), extracted together and sent in one well; one `sample_id`, one CRAM |
| **BC1 sample** | a sample of 6 BC1 plants from one donor cross, identified by pedigree string and donor (no NIL id); the introgression segregates, so at a locus about half the plants are het and half ref |
| **BC2S3 sample** | a sample of 6 plants from one plot of a bulk; a NIL planted in several plots has several samples |
| **library** | samples multiplexed by inline barcode and sequenced together (`library` in the samplesheet) |
| **tissue pool** | a sample seen as a mixture of 6 plants assumed to give equimolar DNA (pool-seq / CRISP sense) |
| **synthetic pool** | samples merged after sequencing into one input, e.g. a donor's witness pool or `B73_skim10` |
| **pool** | alone, only where the method does not distinguish tissue from synthetic pools (CRISP: one input BAM); never a library |
