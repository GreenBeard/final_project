/* Operations supported increment, decrement, logical shift left,
 logical shift right, shift right rotate, shift left rotate, add, subtract,
 and, xor, and or */

/* mode
  000 - or
  001 - and
  010 - xor
  011 - add
  100 - shift left
  101 - shift right
  110 - ???
  111 - ???
*/

module alu_6502(
  input logic[2:0] mode,
  input logic[8:0] input_a,
  input logic[8:0] input_b,
  output logic[8:0] result
);

logic[7:0] adder_a, adder_b, adder_result;
logic adder_c_in, adder_c_out;
ripple_adder_8 adder(
  .A(adder_a), .B(adder_b), .Sum(adder_result), .c_in(adder_c_in),
  .c_out(adder_c_out)
);

assign adder_b = input_b[7:0];
assign adder_a = input_a[7:0];

always_comb begin
  adder_c_in = 1'bx;
  case (mode)
    3'b000: begin
      assert(input_a[8] === 1'bx && input_b[8] === 1'bx);
      result[7:0] = input_a[7:0] | input_b[7:0];
      result[8] = 1'bX;
    end
    3'b001: begin
      assert(input_a[8] === 1'bx && input_b[8] === 1'bx);
      result[7:0] = input_a[7:0] & input_b[7:0];
      result[8] = 1'bX;
    end
    3'b010: begin
      assert(input_a[8] === 1'bx && input_b[8] === 1'bx);
      result[7:0] = input_a[7:0] ^ input_b[7:0];
      result[8] = 1'bX;
    end
    3'b011: begin
      assert(input_b[8] === 1'bx);
      adder_c_in = input_a[8];
      result = { adder_c_out, adder_result };
    end
    3'b100: begin
      assert(input_b === 9'bx);
      result = { input_a[7:0], input_a[8] };
    end
    3'b101: begin
      assert(input_b === 9'bx);
      result = { input_a[0], input_a[8:1] };
    end
    default: begin
      assert(input_a === 9'bx && input_b === 9'bx);
      result = 9'hx;
    end
  endcase
end

endmodule
