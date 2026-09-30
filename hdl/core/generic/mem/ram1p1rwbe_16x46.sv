///////////////////////////////////////////
// ram1p1rwbe_16x46.sv
//
// Purpose: RAM wrapper for instantiating RAM IP
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module ram1p1rwbe_16x46(
  input  logic          CLK,
  input  logic          CEB,
  input  logic          WEB,
  input  logic [3:0]    A,
  input  logic [45:0]   D,
  input  logic [45:0]   BWEB,
  output logic [45:0]   Q
);

   // TODO: replace with the real macro name emitted by your vendor's memory compiler for a 16x46 single-port SRAM
   //generic16x46RAM sramIP (.CLK, .CEB, .WEB, .A, .D, .BWEB, .Q);
   TS1N28HPCPSVTB16X46M4SW sramIP(.CLK, .CEB, .WEB, .A, .D, .BWEB, .Q);

endmodule
