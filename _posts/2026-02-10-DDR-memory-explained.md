---
layout: post
title: "DDR memory explained"
date: 2026-02-09
---

## Introduction

The reason why I wrote this blog is I found a lot of articles and paper in DRAM area tend to use a simplified DRAM model and propose their design over this conceptual model. Honestly speaking, there is no problem with it since academic research and idea brainstorm does not need to consider many complex real-world problems(also, DRAM vendor are always slience on whats going on under the hood). However, I also realized there aren't many article talking about real-world design/manufacture problems in DRAM area. In this case, I am going to talk some of them.

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
9. DRAM chip-level reverse engineering
10. tbd...


## DRAM conceptual model
From the perspective of software programmer, DRAM is just a super long 1D array. If you are into the UNIX philosophy, there's no difference with DRAM or SSD or HDD since they can all being "mmaped" and do read() and write() over it. However, such simplified 1D array is just an illusion given by cache hierarchy since they are cleaver(or big) enough to know the next piece of data CPU want to grab for most of the time. Unfortunantly, cache hierarchy cannot make 100% prediction on future, and when it predict failed, requests needs to goes into the next level. It can be anything connected to NoC, e.g. UART/RDMA/GPU, but for the most of time, it goes into DRAM.

DRAM has a big difference compare with DFF or SRAM array. DFF and SRAM are all digital signal holder and it's easy to send a request in clock cycle 0 and get the data back in clock cycle 1. It's easy to just open an access transistor and pump the data in/out of it. For DRAM, which operate in capacitor for the purpose of storage density and cost control, doesn't have the self-amplification ability as CMOS. It's also more complex to access data from DRAM compare with access data from DFF/SRAM array. 

A single bit storage logic in DRAM would looks like this:

[PICTURE OF 1T1C cell]

Bits(1/0) are stored inside the capacitor in the form of charge. Once the access transistor closed(connected), the charge inside capacitor will be shared with circuit outside through Bitline. Observing the voltage change after connected the access transistor, we can determine if the data inside contain 1 or 0.

Write procedure to a single cell is also easy. Simply drive the correspond bitline with correct voltage can solve the problem. If we want to write 0 then we drive the bitline with a voltage smaller than Vref so capacitor will share the charge to reach equalibrium. If we want to write 1 then we drive bitline with a voltage higher than Vref so it will charge capacitor to reach the equalibrium. If we want to store the bits inside we just need to open(disconnect) the access transisotr, and charge will be kept inside the capacitor.

Above is the operation to access one single bits in DRAM. However, to access a large amount of data and send them to CPU cache subsystem would require a lot of extra jobs. A typical access sequence to DRAM cell is split into following phases:

```c
ACTIVATE -> READ/WRITE -> PRECHARGE
```

This sequence can be applied on DRAM cell array which looks like this:

[PICTURE OF DRAM CELL ARRAY]

During the ACTIVATION phase, the access transistor for a whole row of cell will connect its correspond capacitor with the bitline next to it. Bitlines are all connected with a row buffer which will "buffer" the data in capacitor and they are ready for future READ/WRITE.

During READ/WRITE phase, CPU can read/write from/to the row buffer, and row buffer will reflect the changes made by CPU into those connected capacitor.

During PRECHARGE phase, access transistor will close and buffer will be set into "default" state and ready for next ACTIVATION.

This is a conceptual model of how DRAM works internally.


## Memory controller and DDR commands
As all kinds of storage devices(from DFF array to HDD disk), they are designed as a command receiver which basically receive the requests and bring back data. The way we access DFF array is by pumping it with clock signal and assert R/W port in correct time. For DRAM, we do not have such convenient way to access. Instead, we use specific command to tell DRAM when to do what. These commands is called DDR command.

This can be a weird thing to think about. The way we access memory in C looks like:

```c
int a = *(int*)addr;
```

And even if we write above code into assembly, it would looks like this:

```
ld $t0, 0($a3)
```

There's never any "DDR" command on example above, so who use DDR command?

The answer is memory controller.

Appearantly DRAM itself is not smart enough to understand when CPU said "Please give me data in address 0xdeadbeef". They are optimized for holding as much data as possible and cheap as possible. Typically they do not have the ability to run logics on it. It's relying on CPU to tell what to do next. The command it received from CPU is called DDR command and it looks like this:

```
ACT row x, READ column y, WRITE column z, Close row x
```

There's a small components in CPU side which translate regular memory read/write requests into those sequence of DDR command.

[DIE SHOT OF MC]

DDR commands also have different execution time. They are written in JEDEC DDR standard and they are always constant. For example, ACT tooks 15ns to execute and RD/WR only takes 4ns. Memory controller should handle both the next command and the timing to issue the next command, since DRAM is too "stupid" to figure out what's going on.


## DDR commands timing

There are a lot of timing parameter tied with DDR issue system. They are designed to meet certain kinds of timing&power constraints. This section will explain following DDR timing parameters:

- tCK
- tRAS
- tCAS
- tRCD
- tRP
- tCCD\_S && tCCD\_L
- tREFI
- tRFC
- tRPRE
- tWPRE
- tRRD\_S && tRRD\_L
- tWTR\_S && tWTR\_L
- tFAW
- tCKE
- tCKESR
- tXS
- tXP
- tRTRS
- tRTP
- tWR

There are even more parameters in spec, I just picked some of them which I care the most. 

`tCK` is the period of clock signal. DDR memory does not have its own clock generator and it's relying on CPU's DDR interface to provide a reference clock. tCK can be something like 0.83 or 1.07 depends on DRAM frequency.

