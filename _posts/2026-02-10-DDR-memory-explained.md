---
layout: post
title: "DDR memory explained"
date: 2026-02-09
---

## Introduction

The reason why I wrote this blog is I found a lot of articles and paper in DRAM area tend to raise a simplified DRAM model and propose their design over such conceptual model. Honestly speaking, there is no problem with it since academic research and idea brainstorm does not need to consider many complex real-world problems. However, I also realized there aren't many article talking about those problems. In this case, I am going to talk some of them.

This blog will mainly focus on regular DDR memory, specifically, DDR4. So yeah, no DDR5 or some crazy GDDR or HBM architecture. However, both of them are also interesting to discover and I'll post some papers which I found super helpful.

## Index
1. DRAM conceptual model
2. Memory controller and DDR commands
3. DDR commands timing
4. DRAM hierarchy
5. Conceptual model for subarray
6. Break the conceptual mode for subarray
7. Sense-amplifier
8. DRAM repair
9. tbd...


## DRAM conceptual model
From the perspective of software programmer, DRAM is just a super long 1D array. If you are super into UNIX philosophy, there's no difference with DRAM or SSD or HDD since they can all being "mmaped" and do read() and write() over it once you got a driver. However, such simplified 1D array is just an illusion given by cache hierarchy since they are cleaver(or big) enough to know the next piece of data CPU want to grab for most of the time. However, cache hierarchy cannot make 100% prediction on future, and when it predict failed, requests needs to goes into the next level. It can be anything connected to NoC, e.g. UART/RDMA/GPU, but for the most of time, it goes into DRAM.

DRAM has a big difference compare with DFF or SRAM. DFF and SRAM are all digital signal holder and it's easy to send a request in clock cycle 0 and get the data back in clock cycle 1. It's easy to just open an access transistor and pump the data in/out of it. For DRAM, which operate in capacitor for the purpose of storage density and cost control, doesn't have the self-amplification ability as CMOS. A single bit storage logic in DRAM would looks like this:

[PICTURE OF 1T1C cell]

A typical access sequence to DRAM cell is split into following phases:

```
ACTIVATE -> READ/WRITE -> PRECHARGE
```

This sequence can be applied on DRAM cell array which looks like this:

[PICTURE OF DRAM CELL ARRAY]

During the ACTIVATION phase, the access transistor for a row of cell will connect its correspond capacitor with the bitline next to it. Bitlines are all connected with a row buffer which will "buffer" the data in capacitor and they are ready for future READ/WRITE.

During READ/WRITE phase, CPU can read/write from/to the row buffer, and row buffer will reflect the changes made by CPU into those connected capacitor.

During PRECHARGE phase, access transistor will close and buffer will be set into "default" state and ready for next ACTIVATION.

This is a conceptual model of how DRAM works internally.
