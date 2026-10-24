# Terminology

Plant material and sequencing units, from field to reads. Code, docs and the paper use these words in these senses only.

| term                                    | meaning                                                                                                                                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **bulk**                                | the seed of one BC2S3 NIL (~1 kg), mixed from the ears of its self; one bulk per NIL                                                                                                       |
| **plot**                                | one sowing from a bulk; a NIL can be planted in several plots                                                                                                                              |
| **sample**                              | leaf punches of 6 plants (one per plant), extracted together and sent in one well; one `sample_id`, one CRAM                                                                               |
| **BC1 sample**                          | a sample of 6 BC1 plants from one donor cross, identified by pedigree string and donor (no NIL id); the introgression segregates, so at a locus about half the plants are het and half ref |
| **BC2S3 sample**                        | a sample of 6 plants from one plot of a bulk; a NIL planted in several plots has several samples                                                                                           |
| **library**                             | samples multiplexed by inline barcode and sequenced together (`library` in the samplesheet)                                                                                                |
| **kit**                                 | the library preparation kit, `kit` in the samplesheet: `twist_flexprep` (BC1, BC2S3 batch 2) or `twist_96plex` (BC2S3 batch 1); sets the read structure                                    |
| **tissue pool**                         | a sample seen as a mixture of 6 plants assumed to give equimolar DNA (pool-seq / CRISP sense)                                                                                              |
| **balanced tissue pool**                | a tissue pool whose 6 plants contribute about equally: its donor segments read the expected ALT                                                                                            |
| **unbalanced tissue pool**              | a tissue pool whose donor segments read too little ALT (never too much): unequal plants, dilution, or selection                                                                            |
| **family with balanced tissue pools**   | a donor family whose BC2S3 samples pass the sample introgression dosage check (`docs/decisions.md`, 2026-10-11)                                                                            |
| **family with unbalanced tissue pools** | a donor family whose BC2S3 samples fail that check; flagged, never dropped; kept out of the union curves                                                                                   |
| **sample introgression dosage check**   | ALT read frequency check per BC2S3 sample: <= 4 donor segments; REF <= 3 %, HET 30-55 %, ALT >= 75 % ALT (was "curve rule")                                                                |
| **dilution factor**                     | of a BC2S3 sample: observed / expected ALT in its ALT segments (expected from families with balanced tissue pools)                                                                         |
| **in silico pool**                      | samples merged after sequencing into one input, e.g. a donor's NIL pool or `B73_skim10`                                                                                                    |
| **pool**                                | alone, only where the method does not distinguish tissue from in silico pools (CRISP: one input BAM); never a library                                                                      |
