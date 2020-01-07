//-------------------------------------------------------------------------
//      memory_contents.sv                                               --
//      The memory contents in the test memory.                          --
//                                                                       --
//      Originally contained in test_memory.sv                           --
//      Revised 10-19-2017 by Anand Ramachandran and Po-Han Huang        --
//      Revised 02-01-2018 by Yikuan Chen
//                        spring 2018 Distribution                       --
//                                                                       --
//      For use with ECE 385 Experment 6                                 --
//      UIUC ECE Department                                              --
//-------------------------------------------------------------------------
// Requires SLC3_2.sv
/*import SLC3_2::*;
`include "SLC3_2.sv"*/

module memory_parser #(parameter size = 256) ();

task memory_contents(output logic[15:0] mem_array[0:size-1]);

////////// Test code begin
// Feel free to modify the first few instructions to test specific opcode you want to test.
// e.g. Replace mem_array[0] = opCLR(R0) with mem_array[0] = opADDi(R0, R0, 1) to
//      test ADD instruction (R0 <- R0 + 1).
// See SLC3_2.sv for all the functions you can use to create instructions.
// Note that if you do this, remember to turn "init_external" in test_memory.sv to 1 for
// any of your modifications to take effect.

   mem_array[  0] = 16'h29; /* AND A with 0 */
   mem_array[  1] = 16'h00;

   mem_array[  2] = 16'h69; /* Add A with 13 */
   mem_array[  3] = 16'd13;

   mem_array[  4] = 16'h65; /* Add A with $0 (h29 or d41) */
   mem_array[  5] = 16'h00;

   mem_array[  6] = 16'h4c; /* JMP back to $0 */
   mem_array[  7] = 16'h00;
   mem_array[  8] = 16'h00;

   for (integer i = 9; i <= size - 1; i = i + 1)        // Assign the rest of the memory to 0
   begin
       mem_array[i] = 16'h0;
   end

///////////// Test code end

endtask

endmodule
