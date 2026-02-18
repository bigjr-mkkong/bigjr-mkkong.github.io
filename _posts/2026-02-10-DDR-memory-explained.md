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
7. Sense-amplifier(SA)
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
ACT row x, READ column y, WRITE column z, PRE(precharge) row x
```

Precharge can be understood as "close" a row. This is not true as we went further but for now lets assume it's true.

There's a small components in CPU side which translate regular memory read/write requests into those sequence of DDR command.

[DIE SHOT OF MC]

DDR commands also have different execution time. They are written in JEDEC DDR standard and they are always constant. For example, ACT tooks 15ns to execute and RD/WR only takes 4ns. Memory controller should handle both the next command and the timing to issue the next command, since DRAM is too "stupid" to figure out what's going on.

The way MC issue DDR commands is like a queue. MC will post the command type and when to issue info into a queue, and issuer will send the command out when it's the time. For example, if it's clock 8 right now and I want to issue an RD in clock 12, I will push my request into the queue, and this request will goes out when it's 12 in clock.

It's kinda weird to find each command in DRAM subsystem have a thing called timing. In regular FPGA programming, if we are access one module from another, we only needs a val-rdy handshake to guarantee the timing correctness and data integrity. However, DRAM isn't even cleaver enough to hold massive amount of state of its own banks. In this way, the command sender needs to have some kinds of agreement with receiver, and that's what we called DDR spec (by JEDEC ofc).

## DDR commands timing

There are a lot of timing parameter tied with DDR issue system. They are designed to meet certain kinds of timing&power constraints. This section will explain following DDR timing parameters:

- tCK
- tRAS
- tCAS(tCL)
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

`tRAS` stand for "Row Access Strobe". It represent the minimum amount of time between ACT and PRE. This parameter limits MC cannot issue an ACT and PRE back-to-back. It has to wait until the tRAS passed. The reason for such limitation will be explained when we talking about transistor level design.

`tCAS`(or tCL) stand for "Column Address Strobe". It measure the latency between the time when MC issue the RD and gets the data back, AKA the latency taken for a single read.

`tRCD` stand for "RAS to CAS delay", it measure the time taken between ACT being issued and row ready for column command. It's easy to confuse with tRAS. The difference is, PRE is not column command, and it needs to wait until tRAS as satisfied, while RD/WR are column command, which only needs to wait until tRCD is satisfied. The reason for this will be covered when we talk about transistor level design.

`tRP` stand for "Row Precharge". It means the time taken for single PRE command. Be aware the earlist timing to have precharge is tRAS after the last ACT. I will also cover the Precharge operation when we talked about transistor level design for Sense Amplifier.

`tCCD_S && tCCD_L` stand for "Column to Column Delay(Short/Long)". This marks the minimum timing between issue two column command(RD/WR). In this case, MC cannot issue RD/WR command too fast, since that would cause problems in DRAM data integrity. The reason why we need Short/Long marks is the new technology introduced by DDR4 called bank groups. Bank group can be understand as an intermediate layer between channel and bank. Assume we have 32 banks per channel, to have 4 bank groups means we have 8 banks goes into one bank group. Bank groups share teh same address decoder, they also have their own local IO buses and SAs. Bank group are designed to fix the scalability issue of DRAM, as the storage density increase, the corresponding address decoder as well as bus wire also gets bigger. Designer divide whole structure into bank groups to keep boosting DRAM frequency.

It's faster for two RD to goes into different bank groups other than same one, because they do not have to share the same decoder and same local bus(still share the global bus since there's only one global bus, but it's okey). In this case, `tCCD_S` is the minimum latency between two column command being issued when they target on different bank group, and `tCCD_L` is the the minimum latency between two column command being issued when they target on same bank group.

`tREFI` stand for "Refresh Interval". As the name reveal, it stand for how often a REFRESH command must be issued. As you probably already know, DRAM is neither self-amplified storage as SRAM/DFF nor permanent storage media like magnetic tape(or carving words on stones?). It needs to constantly read out what it got and re-amplify them. `tREFI` marks the period of doing such operation.

`tRFC` stand for "ReFresh Cycle time". It stand for the time taken for DRAM to perform refresh. When DRAM performing refresh, no other DDR commands can be served and DRAM is basically passed away for `tRFC` amount of time.

`tRPRE` stand for "Read PREamble time", which marks the pre-sampling delay from higher level. This is an internal timing parameter for interfacing which sit inside tCAS. The reason why we need to wait a while between data valid and sampling start is, DQ(data pin) are synchronized with DQS, but CK is the clock signal when we talked about DRAM operation like ACT/PRE/RD/WR. CK needs to travel a really long route from cpu to every DRAM chip, which can have serious clock skew problem. This means the CK we referred in sampling logic is not reliable for high-speed signal. In this case, DDR gives us another new clock signal called DQS. As the name suggested, it's the Sampling clock for DQ. DQS `tRPRE` is the time taken for DRAM to reset sampling logic and it's necessary for safe sampling to valid data.

`tWPRE` stand for "Write PREamble time". It's basically same as tRPRE. The only place to notice is, DQ is a bidirectional signal wire, so for each column command, we need to go through the complete reset procedue of sampling. This means, both tRPRE and tWPRE is a part of tCAS.

There appearantly needs some CDC designs done to bridge two clock domain together. However, DRAM vendors are always slient on what exactly happening under the hood so we cannot know(We can make best guess tho). There are some research about DRAM reverse-engineering, but they mainly focused on subarray level design instead of interfacing. I'll talk about that research in this blog. And I really hope either vendor release more DRAM internal designs, or someone use SEM(scanning electron microscopy) to peel the DRAM and look it up.

`tRRD_S && tRRD_L` stand for "Row to Row Delay(Short/Long)". It measure the minimal time between two success ACT being issued. `tRRD_S/L` bound the frequency of issue ACT into different bank. Just like `tCCD_S/L` differ the access into same/different bank group, `tRRD_S/L` also differ the ACT goes into same/different bank group. The reason is also the same: different bank groups can have less confliction in parts use.


