-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Gabriel Biel <XBIELG00>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	signal prog_addr  : std_logic_vector (11 downto 0) := (others => '0'); 
	signal prog_inc  : std_logic := '0';
	signal prog_dec  : std_logic := '0';

  signal ptr_addr    : std_logic_vector(11 downto 0) := (others => '0');
	signal ptr_inc     : std_logic := '0';
	signal ptr_dec     : std_logic := '0';
  
  signal mx1_sel : std_logic := '0'; 
  signal mx2_sel : std_logic_vector (1 downto 0) := "00";
  

  -- 
	type fsm_state is (
		start_s,
		fetch_s,
		decode_s, --decode data on prog pointer
		value_inc_s,value_inc1_s,value_inc2_s,value_inc3_s,--states to handle incrementation
		value_dec_s,value_dec1_s,value_dec2_s, --states to handle decrementation
		pointer_inc_s, -- inc pointer
		pointer_dec_s, -- dec pointer
		while_condition_s, --checks condition
		while_skip_s, --skip in case condition = 0
		while_repeat_s, --move pointer until [
		while_end_s, --check condition 
    do_while_end_s, --check condition
    do_while_repeat_s, --move back pointer until )
		input_s, input2_s,
		print_s, print2_s, print3_s, 
		null_s
	);
	signal state  : fsm_state := start_s;
	signal nstate : fsm_state := start_s;

  begin

-- pc                      
    prog : process(CLK,RESET,prog_inc,prog_dec) is
    begin
      if RESET = '1' then
        prog_addr <= (others => '0');
      elsif rising_edge(CLK) then
        if prog_inc = '1' then
          prog_addr <= prog_addr + 1;
        elsif prog_dec = '1' then
          if prog_addr /= "000000000000" then
          prog_addr <= prog_addr - 1;
          end if ;
        end if;
      end if;    
    end process ;

  -- ptr             
  ptr : process(CLK,RESET,ptr_inc,ptr_dec) is
  begin
    if RESET = '1' then
      ptr_addr <= (others => '0');
    elsif rising_edge(CLK) then
      if ptr_inc = '1' then
        ptr_addr <= ptr_addr + 1;
      elsif ptr_dec = '1' then
        ptr_addr <= ptr_addr - 1;
      end if;
    end if;    
  end process ; 

  -- mx1
  with mx1_sel select
  DATA_ADDR <= "0" & prog_addr when '0', "1" & ptr_addr when '1', (others => '0') when others; 
  
  -- mx2 inc/dec current value
  with mx2_sel select
  DATA_WDATA <= IN_DATA when "00", (DATA_RDATA +1) when "01", (DATA_RDATA -1) when "10", "00000000" when others;

      
  -- fsm
  state_logic: process (CLK, RESET, EN) is
    begin
      if RESET = '1' then
        state <= start_s;
      elsif rising_edge(CLK) then
        if EN = '1' then
          state <= nState;
        end if;
      end if;
    end process;

	next_state_logic: process (state, OUT_BUSY, IN_VLD, DATA_RDATA) is
    begin
      prog_inc <= '0';
      prog_dec <= '0';
      ptr_inc <= '0';
      ptr_dec	<= '0';
      DATA_EN <= '0';
      DATA_RDWR <= '0';
      IN_REQ <= '0';
      OUT_WE <='0';
      -- OUT_DATA <= (others => '0');

        case state is
          when start_s =>
            nState <= fetch_s;
          when fetch_s =>
            mx1_sel <= '0'; -- get prog data
            DATA_EN <= '1'; -- read new
            nState <= decode_s;
          when decode_s =>
            DATA_EN <= '1'; -- read prog data
            case DATA_RDATA is
              when x"3E" => -- >
                nState <= pointer_inc_s;
              when x"3C" => -- <
                nState <= pointer_dec_s;
              when x"2B" => -- +
                nState <= value_inc_s;
              when x"2D" => -- -
                nState <= value_dec_s;
              when x"5B" => -- [
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= while_condition_s;
              when x"5D" => -- ]
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= while_end_s;
              when x"28" => -- (
                prog_inc <= '1'; -- do first
                nState <= fetch_s;
              when x"29" => -- )
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= do_while_end_s;
              when x"2E" => -- .
                nState <= print_s;
              when x"2C" => -- ,
                nState <= input_s;
              when x"00" => -- NULL
                nState <= null_s;
              when others => -- skip anything else
                prog_inc <= '1';
                nState <= fetch_s;
            end case;
      
          when pointer_inc_s =>
            prog_inc  <= '1';
            ptr_inc <= '1';
            nState  <= fetch_s;
            
          when pointer_dec_s =>
            prog_inc  <= '1';
            ptr_dec <= '1';
            nState  <= fetch_s;
    
          when value_inc_s =>
            mx1_sel <= '1'; -- look at data
            nState <= value_inc1_s;
          
          when value_inc1_s =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get cur data 
            nState    <= value_inc2_s;

          when value_inc2_s =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get cur data 
            mx2_sel <= "01"; --inc
            nState    <= value_inc3_s;
            
          when value_inc3_s =>
            DATA_EN <= '1';
            DATA_RDWR <= '1'; --write cur data
            prog_inc  <= '1'; -- next 
            nState  <= fetch_s;
    
          when value_dec_s =>
            mx1_sel <= '1'; -- look at data
            DATA_EN <= '1';
            nState <= value_dec1_s;

          when value_dec1_s =>
            mx2_sel <= "10"; --dec
            DATA_EN <= '1';
            nState    <= value_dec2_s;

          when value_dec2_s =>
            DATA_EN <= '1'; 
            DATA_RDWR <= '1'; --write
            prog_inc <= '1'; --next
            nState  <= fetch_s;
    
          when print_s =>
            mx1_sel <= '1'; --look at data
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get
            nState  <= print2_s;
    
          when print2_s =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get
            if OUT_BUSY = '1' then --wait until not busy 
              DATA_EN <= '1'; 
              DATA_RDWR <= '0';
              nState  <= print2_s;
            else
              OUT_DATA <= DATA_RDATA; --printout
              OUT_WE <= '1'; -- enable writing
              prog_inc <= '1'; -- next
              nState <= fetch_s;
            end if;

          when input_s =>
            mx1_sel <= '1'; -- get data
            mx2_sel <= "00"; -- data fom input
            nState    <= input2_s;

          when input2_s =>
            IN_REQ    <= '1'; 
            if IN_VLD = '1' then -- wait until valid
              DATA_EN <= '1';
              DATA_RDWR <= '1'; --write&update
              prog_inc <= '1'; --next
              nState <= fetch_s;
              else
              nState <= input2_s; --get back & req data
            end if;
    
          when while_condition_s =>
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --when value is zero skip until ]
              mx1_sel <= '0'; --get prog data
              nState  <= while_skip_s;
            else
              prog_inc <= '1'; --move pointer
              nState  <= fetch_s;
            end if;
            
          when while_skip_s => --skip 
            DATA_EN <= '1'; --read prog data
            prog_inc <= '1'; -- move pointer
            if DATA_RDATA = x"5D" then --check for closing parse
              nState  <= fetch_s; --continue with the program
            else
              nState <= while_skip_s;
            end if;
            
          when while_end_s =>
            mx1_sel <= '1';--get prog data
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --continue with program
              prog_inc <= '1'; --move pointer
              nState <= fetch_s;  
            else
              mx1_sel <= '0';--get prog data
              nState <= while_repeat_s;
            end if;
            
          when while_repeat_s =>
            DATA_EN <= '1';
            if DATA_RDATA = x"5B" then --if [ start again  
              prog_inc <= '1';
              nState <= fetch_s;
            else
              prog_dec <= '1';
              mx1_sel <= '1';--get prog data
              nState <= while_end_s;
            end if;            
            
          when do_while_end_s =>
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --continue with program
              prog_inc <= '1'; --move pointer
              nState <= fetch_s;  
            else
              mx1_sel <= '0';--get prog data
              nState <= do_while_repeat_s;
            end if;
            
          when do_while_repeat_s =>
              DATA_EN <= '1';
            if DATA_RDATA = x"28" then --if ( start fetching again
              prog_inc <= '1';
              nState <= fetch_s;
            else
              prog_dec <= '1';
              nState <= do_while_repeat_s;  -- move back until (
            end if;            
            
          when null_s =>
            if RESET = '1' then
              nState <= start_s;
            end if;

          when others =>
            nState <= null_s;
        end case;

  end process;
---fsm---

  


end behavioral;
