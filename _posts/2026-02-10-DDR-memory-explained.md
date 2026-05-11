---
layout: post
title: "DDR Memory Explained"
date: 2026-02-09
---

## Introduction

The reason I wrote this blog is that I've found a lot of articles and papers in the DRAM space tend to use an overly simplified, conceptual DRAM model. Honestly speaking, there is no problem with it. Academic research and brainstorming don't always need to get bogged down by complex, real-world constraints (plus, DRAM vendors are famously secretive about what goes on under the hood, so details are scarce). 

However, I realized that without a complete background introduction, it's hard to get a full picture of what DDR DRAM actually is, and what the real pitfalls and constraints are in DRAM design. In this blog, I am going to bridge that gap a little bit.

We will focus mainly on regular DDR memory—specifically, DDR4. So no DDR5, GDDR, or HBM architectures today. However, those are also incredibly interesting, and I'll post references to papers I found super helpful. 

It's also worth mentioning that there are plenty of other exotic memory technologies like STT-MRAM (Spin-Transfer Torque), 2T0C/3T0C DRAM, Memristors, and PCM (Phase Change Memory). While they are incredibly fascinating to talk about, they are out of scope for this post. For the duration of this blog, every memory cell we look at will strictly be the traditional 1T1C design

This will also be a periodically updated post. Since vendors are so quiet, there is always something new waiting to be discovered. All updated content will be placed in the Updates section.

## Index
1. [The DRAM Conceptual Model](#the-dram-conceptual-model)
2. [Memory Controllers and DDR Commands](#memory-controllers-and-ddr-commands)
3. [DRAM Hierarchy](#dram-hierarchy)
4. [DDR Commands Timing](#ddr-commands-timing)
5. [The Conceptual Model for Subarrays](#the-conceptual-model-for-subarrays)
6. [Breaking the Subarray Conceptual Model](#breaking-the-subarray-conceptual-model)
7. [The Sense Amplifier](#the-sense-amplifier)
8. [DRAM Repair](#dram-repair)
9. [DRAM Chip-Level Reverse Engineering](#dram-chip-level-reverse-engineering)
10. [Finale](#finale)
11. [Updates](#updates)

---

## 1. The DRAM Conceptual Model

From the perspective of a software programmer, DRAM is just a super long 1D array. Software operates under the illusion of a flat address space, doing basic read and write operations. However, this simplified 1D array is just an illusion maintained by the cache hierarchy. Caches rely on spatial and temporal locality (along with clever memory disambiguity mechanism) to guess the next piece of data the CPU will want. Unfortunately, caches cannot predict the future with 100% accuracy. When there's a cache miss, the request goes to the next level, which is main memory (DRAM) for most of cases.

DRAM is very different from a D-Flip Flop (DFF) or an SRAM array. DFFs and SRAM are digital signal holders; it's easy to send a request in clock cycle 0 and get the data back in clock cycle 1. You just open an access transistor and pump the data in or out. DRAM, however, operates using capacitors to maximize storage density and keep costs low. Capacitors do not have the self-amplification abilities of CMOS transistors, making data access much more complex.

A single-bit storage logic in DRAM looks like this:

> [Placeholder: Picture of 1T1C cell]

Bits (1 or 0) are stored inside the capacitor in the form of an electrical charge. Once the access transistor is closed (connected), the charge inside the capacitor is shared with the outside circuit through a wire called a **Bitline**. By observing the voltage change after the transistor connects, we can determine if the cell held a 1 or a 0.

Writing data to a single cell is just as straightforward conceptually. We drive the corresponding bitline with a specific voltage. To write a `0`, we drive the bitline with a voltage lower than the reference voltage (Vref), allowing the capacitor to discharge and reach equilibrium. To write a `1`, we drive the bitline with a voltage higher than Vref to charge the capacitor. Opening (disconnecting) the access transistor traps the charge inside.

However, accessing large amounts of data to send to the CPU requires extra steps. A typical access sequence for a DRAM cell is split into three phases:

```
ACTIVATE -> READS/WRITES -> PRECHARGE
```

This sequence is applied to a DRAM cell array, which looks like this:

> [Placeholder: Picture of DRAM cell array]

* **ACTIVATION:** The access transistors for an entire row of cells connect their corresponding capacitors to the adjacent bitlines. These bitlines are connected to a "row buffer," which catches and holds the capacitor data, making it ready for a READ or WRITE.
* **READ/WRITE:** The CPU reads or writes data to/from this row buffer. The row buffer then reflects these changes back into the connected capacitors.
* **PRECHARGE:** The access transistors close, and the bitlines/buffers are reset to a "default" state, ready for the next ACTIVATE command.

This is the baseline conceptual model of how DRAM works internally.

---

## 2. Memory Controllers and DDR Commands

Like all storage devices, DRAM is designed as a command receiver. But while we access a DFF array simply by pumping it with a clock signal and asserting a Read/Write pin, DRAM requires specific commands. These are called **DDR commands**.

This can feel weird to think about. In C, memory access looks like this:
```c
int a = *(int*)addr;
```

In assembly, it looks like this:

```c
ld $t0, 0($a3)
```

There are no "DDR commands" here. So who issues them? The Memory Controller (MC).

DRAM chips are not smart enough to understand when the CPU says, "Please give me the data at address `0xdeadbeef`. They are optimized to hold massive amounts of data as cheaply as possible; they do not run complex logic. They rely entirely on the CPU's memory controller to tell them exactly what to do. The sequence the MC sends looks more like this:

```
ACT row x, READ column y, WRITE column z, PRECHARGE row x
```

There is a small component on the CPU die that translates regular memory requests into these DDR command sequences.

    [Placeholder: Die shot of Memory Controller]

DDR commands take different amounts of time to execute, as dictated by JEDEC DDR standards. For example, an ACT (Activate) might take 15ns, while a RD/WR (Read/Write) might only take 4ns. The memory controller must manage a queue, tracking exactly what to send and when it is safe to send it, because the DRAM is too "dumb" to manage its own state safely. If MC wants to issue a Read at clock cycle 12, it pushes the request to a queue, and the issuer sends it precisely at cycle 12.

## 3. DRAM Hierarchy

Conceptually, DRAM is a giant matrix of 1T1C (1 Transistor, 1 Capacitor) cells controlled by extremely long wordlines and bitlines. In reality, building such a giant flat matrix is impossible to manufacture cheaply or operate quickly. Therefore, designers split these cells into multiple layers. In traditional DDR4, the hierarchy is: **Channel -> Rank -> Bank Group -> Bank -> Subarray -> Row -> Column**.

(Note: HBM lacks ranks, and LPDDR lacks bank groups. We will focus strictly on DDR4 here).

- **Channel**: The highest level of the hierarchy. A channel typically takes up at least one DIMM slot. Two different channels are completely separate pieces of hardware and share no global buses.

- **Rank**: A group of DRAM chips (the black squares on the PCB) working together. If you see "DDR4 x16", it means each chip provides 16 bits per cycle. Since a single rank needs to provide a 64-bit data bus to the CPU, you need 4 of these chips (64 / 16 = 4) to form one rank. Only one rank on a channel can actively drive data to the data pins (DQ) at a time.

- **Bank Group**: Introduced in DDR4 to increase bandwidth. As capacities grew, address decoders and bus wires became too long and slow. A Bank Group clusters several banks together so they can share local I/O buses and decoders. By alternating commands between different Bank Groups, the memory controller can pipeline requests much faster than sending them to the same group.

- **Bank**: The most important operational hierarchy. A bank consists of multiple subarrays and sense amplifiers. Banks can hold their own independently opened row buffers, though only one bank can drive a Bank Group's output at a time.

- **Subarray**: The actual core where the 1T1C matrix lives. A subarray usually has a width of 8K cells and a height of 256 or 512 rows. Each subarray has its own local row buffer (sense amplifiers). If a CPU requests data from a currently open row, it's incredibly fast. If it misses, the bank must precharge the current row and activate the new one.

## DDR Commands Timing

Because DRAM can't track its own state safely, the memory controller and the DRAM must follow a strict timing agreement: the JEDEC DDR spec. These parameters exist to meet physical circuit limitations and power constraints.

Now that we understand the hierarchy (like Bank Groups), these timings will make more sense:


- **tCL(Clock Period)**: DRAM relies on the CPU for its reference clock. tCK is the length of one clock cycle (e.g., 0.83ns or 1.07ns depending on frequency).

- **tRAS(Row Access Strobe)**: The minimum time between an ACT and a PRE command. You cannot open a row and instantly close it; the physical circuits need time to properly share and restore charge.

- **tCAS or tCL (Column Address Strobe/CAS latency)**: The delay between issuing a READ command and receiving the first chunk of data. Because data is sent in bursts, tCAS only measures the time to the first beat, not the entire transfer.

- **tCWL(CAS Write Latency)**: The write equivalent of tCAS. The time between issuing a WRITE and when the DRAM expects the first chunk of data.

- **tRCD(RAS to CAS Delay)**: The time between issuing an ACT command and when the row is actually ready to accept READ/WRITE (column) commands.

- **tRP(Row Precharge)**: The time it takes to execute a PRECHARGE command, safely closing the row and resetting the bitlines.

- **tCCD\_S & tCCD\_L (Column to Column Delay - Short/Long)**: The minimum time between issuing two column commands. `tCCD_S` is shorter because the two commands target different Bank Groups (less hardware conflict). `tCCD_L` is longer because they target the same Bank Group, forcing them to share local routing and decoders.

- **tREFI(Refresh Interval)**: How often a REFRESH command must be issued. Because capacitors leak charge over time, they must be periodically read and rewritten.

- **tRFC(Refresh Cycle Time)**: The time it takes for the DRAM to actually perform the refresh operation. During this time, the DRAM is essentially offline and cannot serve read/write requests.

- **tRPRE & tWPRE(Read/Write Preamble)**: The clock signal (CK) travels long distances and suffers from skew. Therefore, data relies on a separate data strobe signal (DQS). The preamble is the time taken to reset and align the sampling logic for DQS before data transmission begins.

- **tRRD\_S & tRRD\_L(Row to Row Delay - Short/Long)**: The minimum time between two successive ACT commands. Like tCCD, it is shorter for different Bank Groups and longer for the same Bank Group.

- **tWTR\_S & tWTR\_L (Write to Read Delay)**: The delay required if you want to READ immediately after a WRITE. The data from a WRITE must be safely driven into the sense amplifiers and back into the physical capacitors ("Write Recovery") before a new READ can safely occur.

- **tRTP (Read to Precharge)**: Ensures the memory controller doesn't issue a PRECHARGE while a READ is still happening, which would flush the data out before it finishes transmitting.

- **tWR (Write Recovery Delay)**: The time from the end of a write burst to when a PRECHARGE can be safely issued. If you precharge too early, the bitlines reset before the new charge is fully locked into the capacitors, causing data loss.

- **tFAW (Four-Activate Window)**: A rolling time window that limits the memory controller to a maximum of four ACT commands within a specific timeframe. This is primarily to prevent drawing too much current at once and overloading the Power Delivery Network (PDN).

## The Conceptual Model for Subarrays

The subarray is the actual matrix of 1T1C cells. Conceptually, when we want a cache line (64 bytes) from DRAM, an entire row (usually 8Kb) in the target subarray is activated, and the DRAM plucks the target cache line out of that row.

    [Placeholder: Subarray Picture]

When the DRAM needs to access a different row, it must first precharge. The precharge controller electronically disconnects the active capacitors to trap their charge, then drives the bitlines back to a reference voltage by shorting the amplifiers. After tRP, the MC issues a new ACT command, connecting a new row of capacitors to the bitlines. The charge flows into the local row buffer (an array of Sense Amplifiers) and is latched there.

A column selection logic controls which specific part of that 8Kb local row buffer is routed out to the global bitline (bank interface).

Normally, one subarray can only have one activated row, and one bank can only have one activated subarray. Activating multiple rows/subarrays simultaneously would result in uncontrolled charge sharing and corrupted data. This basic conceptual model is enough to explain famous phenomena like Rowhammer attacks or ComputeDRAM. But if you want to understand real DRAM design, we need to go deeper.

## Breaking the Subarray Conceptual Model

Actually, a lot of the conceptual model above doesn't happen quite like that in the real world. Once you dive into custom subarray-level DRAM design, hidden constraints emerge.

### Incorrect Assumption 0: The Subarray is the lowest level of the hierarchy

It would be neat if the subarray were the final level. However, a single activation signal cannot travel down an 8K-cell-wide wordline without losing signal integrity. Furthermore, dedicating a massive wordline driver to every single row is not area-efficient. Instead, vendors(afaik) divide subarrays into multiple **MATs**.

    [Placeholder: Picture of MATs in subarray]

MATs are smaller squares of bitcells. Multiple MATs stack together to form a subarray. To increase density, vendors split wordlines into **Main Wordlines** and **Sub-Wordlines**. For example, out of 512 rows, there might be 256 main wordlines and 2 sub-wordlines. These feed into an AND gate local to the MATs. A row is only driven when both the main and sub-wordline select it.

    [Placeholder: Picture of Main/Sub-Wordlines]

**The Implication**: We cannot have fine-grained control over row activation. If we want to activate Row 0 and Row 3, but they share wordline logic with Row 2, we physically cannot activate them without also activating Row 2. Many academic proposals assume fine-grained activation is possible, but in reality, they would have to account for extremely specific data placement to work around this hardware limitation.

### Incorrect Assumption 1: Subarrays have isolated row buffers

In our conceptual model, each subarray has its own dedicated row buffer. In reality, to save space, modern open-bitline architectures put half of the sense amplifiers on one side of a subarray and let the adjacent subarray share them.

    [Placeholder: Picture of SA Sharing]

Another reason for this is that sense amplifiers need a reference voltage (Vref) to detect tiny voltage perturbations. DRAM uses the idle, precharged bitline from the adjacent subarray as this reference. Therefore, if Subarray B is activated, Subarrays A and C lose half of their bandwidth because their bitlines are being used as a Vref for Subarray B.

**The Implication**: If a paper proposes activating multiple specific subarrays simultaneously, it will fail if those subarrays are adjacent and rely on shared sense amplifiers.

### Incorrect Assumption 2: The Global I/O (GIO) bus is wide

The GIO connects the subarray's column selection logic to the bank interface. Diagrams often depict it as a massive bus. In reality, bank interfaces are incredibly small to save physical area. Moving data between subarrays over this narrow bus requires sending it in tiny chunks, latching it at the bank level, and trickling it into the target subarray. It entirely bottlenecks the massive internal bandwidth of the subarray itself.

    [Placeholder: Picture of Narrow GIO]

---
We can see, subarray level design should be carried out in cautions. We can have all crazy designs, but we need to be careful on these hidden constraints and clarify our assmption.

This is not even a full list of constraints. More constraints will be reveal in future chapters when we talked about transistor level design and reverse-engineering of today(2026)'s commercial DDR DRAM.



## The Sense Amplifier

The Sense Amplifier (SA) is the unsung hero of DRAM. Because a tiny capacitor only creates a minute voltage perturbation on a bitline, an SA is required to sense that tiny change and amplify it into a full-swing digital signal (VDD or 0) to drive peripheral logic.

Here is a full picture of a traditional SA:

    [Placeholder: Picture of Full SA]

Eww..., that's a lot. Maybe we can divide them into smaller parts.

A typical SA consists of three parts: a **cross-coupled amplifier**, a **precharge circuit**, and a **column selection circuit**.


### Cross-Coupled Amplifier

[Placeholder: Picture of Cross-coupled amplifier]

This consists of two cross-coupled NOT gates. Right before amplification, the Bitline (BL) and inverse Bitline (BLB) are precharged to exactly `VDD/2`. When the wordline opens, the capacitor causes a slight voltage shift on the BL. We then pull the P-sense and N-sense amplifier nodes to full VDD and 0. Because of the cross-coupled nature, the side with the slightly higher voltage turns on its transistor faster, creating a positive feedback loop. Rapidly, the tiny perturbation is slammed into a full digital 1 or 0, effectively latching the data.

The device level design ensure the transistor used in sense amplifier would have a high enough gain by the choice of materials and length of wires. I will add more details on this part once I figured out how to write latex inside markdown :)

Another thing need to be noticed is there's only one BL can be sensed at one time, as another BL need to be functioned as reference voltage and need to remain the same.

### Pecharge Circuit

[Placeholder: Picture of Precharge circuit]

It's a piece of deadly simple circuit, which basically shorts both BL and BLB with `Vblp` when EQ(Equalizer) is on. `Vblp` is always in `VDD/2` so as we can see the mission of precharge circuit is to set a initial state of amplifier so the small pertubation on BL will be "catched" by the NMOS.

Although it looks easy, precharge operation can be really slow during the actual use. BL usually are really long wire in the design of DRAM so each unit length of BL can have some parasite capacitance on it. The procedure of precharge usually needs to discharge the parasite capacitor one by one, which can be a main influence on circuit performance when the design scale up.

### Column seletion circuit

[Placeholder: Picture of Column selector]

There really isn't a lot to talked about in Column Selection Unit. It's basically just two NMOS act like a switch to control the output of amplifier. Many tutorials would even skip it due to its simplicity. However, there's a really intersting story I would like to share about this circuit in the chapter below about it.

---
When we put all three parts above together, we can see the sense amplifier actually behave as a latch. In fact, this is the main reason why we can have fast read/write when DRAM row buffer hit. When we are accessing to the address which being mapped into a group of already-opened sense amplifier, it's basically just like the access to a latch array. But if we are accessing to the address which is not inside any already-opened sense amplifier, we need to repeat the procedure of PRECHARGE and ACTIVATE.

Another thing we can see is by the time we RD/WR data from/to the amplifier, the change will be reflected back to the BL. As WL keeps open during the RD/WR. voltage change in BL being reflected back to DRAM capacitor. In this case, MAT level DRAM cell can actually response to RD/WR in almost immediately. It's only the PRECHARGE and ACTIVATE cause most of the latency during the random DRAM access.

## DRAM Repair

Like CPUs and GPUs, DRAM chips are not immune to manufacturing defects. When Intel or AMD find a flawed core or L3 cache block, they simply fuse it off and sell the chip as a lower-tier product.

DRAM relies on extreme cost-efficiency, so adding complex testing/muting logic per MAT is too expensive in terms of area, and throwing away an entire bank for one dead cell is wasteful. The solution is DRAM Repair via Redundancy.

Manufacturers build slightly more rows and columns than the spec requires. During factory testing, if a defective cell is found, the manufacturer permanently fuses off that row or column and programs the address decoder to reroute traffic to a redundant row/column.

    [Placeholder: Picture of DRAM Repair]

**The Implication**: The CPU never actually knows which physical row it is accessing. A physical address map might calculate that data lives in Row 10, but if Row 10 was repaired at the factory, the data might actually be sitting in Redundant Row 515. This ruins certain In-Memory Computing proposals (like RowClone) that require precise physical alignment of data, because the user cannot guarantee where the data physically resides.

Again, DRAM vendors are always slient about this fact so it's really hard for us outside fab to know what kinds of repair are they really using. Some of them might have subarray level repair which only map defected rows within subarray, while others might have bank level repair which re-route defected rows into another subarray.


## DRAM Chip-Level Reverse Engineering

While papers like DRAMScope do "soft" reverse engineering by sending custom DDR command sequence via FPGA to map out behaviors, physical reverse engineering is much rarer. A fascinating paper published in ISCA '24, HiFi-DRAM, used Scanning Electron Microscopy (SEM) and Focused Ion Beam (FIB) to physically slice open a modern DRAM chip layer by layer like lasagna and photograph its actual layout to create a 3D model of their ROI(btw it's a wrong way to enjoy lasagna ;)).

### OCSA (Offset-Cancellation Sense Amplifier)

The paper revealed that modern DDR5 memory has moved away from the traditional SA design. In theory, NMOS and PMOS transistors are perfectly symmetric. In reality, manufacturing variance causes their threshold voltages (Vth) to differ. This mismatch can cause the SA to latch the wrong value when sensing a tiny capacitor charge.

To fix this, modern DRAM uses an Offset Canceling SA (OCSA). Before charge sharing occurs, the circuit briefly connects the gates and drains of the transistors, forcing them to balance their voltages to perfectly match their unique physical Vth, canceling out manufacturing variations.

[Placeholder: Picture from paper of OCSA]

### Column Select Circuit (CSL) Placement

Remember the Column Selection Unit from Chapter 7? Standard diagrams show it placed after the amplifier. However, HiFi-DRAM discovered that physical layouts often place the bit selection unit before the amplification stage. This limits power consumption and allows manufacturers to use a more unified choice of CMOS devices that match specific voltage tolerances, simplifying fabrication.

[Placeholder: Picture from paper of CSL]

---
This is a really interesting paper and I encourage everyone who interested in DRAM to read it. Another reason I choose this paper is it's published in ISCA'24 and is relativelty new by the time when this blog was written.

## Finale
Many software developers view DRAM as "not important" because it lacks the architectural glamour of a CPU or GPU. However, DRAM is a perfect example of how an ideal, conceptually simple circuit faces a mountain of complex physical, timing, and manufacturing constraints when scaled up to real-world products.

This blog is only a small glance into the complex world of VLSI and physics. I will find a chance to write about HBM and GDDR in the future, as they follow completely different design stories, constraints, and purposes. Most importantly, they are terribly cool.

## Updates
(This section is reserved for updates after the blog is published)
