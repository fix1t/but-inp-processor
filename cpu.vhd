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
		fsm_start,
		fsm_fetch,
		fsm_decode, --decode data on prog pointer
		fsm_value_inc,fsm_value_inc1,fsm_value_inc2,fsm_value_inc3,--states to handle incrementation
		fsm_value_dec,fsm_value_dec1,fsm_value_dec2, --states to handle decrementation
		fsm_pointer_inc, -- inc pointer
		fsm_pointer_dec, -- dec pointer
		fsm_while_condition, --checks condition
		fsm_while_skip, --skip in case condition = 0
		fsm_while_repeat, --move pointer until [
		fsm_while_end, --check condition 
    fsm_do_while_end, --check condition
    fsm_do_while_repeat, --move back pointer until )
		fsm_input, fsm_input2,
		fsm_print, fsm_print2, fsm_print3, 
		fsm_null
	);
	signal state  : fsm_state := fsm_start;
	signal nstate : fsm_state := fsm_start;

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
        state <= fsm_start;
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
          when fsm_start =>
            nState <= fsm_fetch;
          when fsm_fetch =>
            mx1_sel <= '0'; -- get prog data
            DATA_EN <= '1'; -- read new
            nState <= fsm_decode;
          when fsm_decode =>
            DATA_EN <= '1'; -- read prog data
            case DATA_RDATA is
              when x"3E" => -- >
                nState <= fsm_pointer_inc;
              when x"3C" => -- <
                nState <= fsm_pointer_dec;
              when x"2B" => -- +
                nState <= fsm_value_inc;
              when x"2D" => -- -
                nState <= fsm_value_dec;
              when x"5B" => -- [
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= fsm_while_condition;
              when x"5D" => -- ]
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= fsm_while_end;
              when x"28" => -- (
                prog_inc <= '1'; -- do first
                nState <= fsm_fetch;
              when x"29" => -- )
                mx1_sel <= '1'; --get ptr data
                DATA_EN <= '1'; --read ptr data
                nState <= fsm_do_while_end;
              when x"2E" => -- .
                nState <= fsm_print;
              when x"2C" => -- ,
                nState <= fsm_input;
              when x"00" => -- NULL
                nState <= fsm_null;
              when others => -- skip anything else
                prog_inc <= '1';
                nState <= fsm_fetch;
            end case;
      
          when fsm_pointer_inc =>
            prog_inc  <= '1';
            ptr_inc <= '1';
            nState  <= fsm_fetch;
            
          when fsm_pointer_dec =>
            prog_inc  <= '1';
            ptr_dec <= '1';
            nState  <= fsm_fetch;
    
          when fsm_value_inc =>
            mx1_sel <= '1'; -- look at data
            nState <= fsm_value_inc1;
          
          when fsm_value_inc1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get cur data 
            nState    <= fsm_value_inc2;

          when fsm_value_inc2 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get cur data 
            mx2_sel <= "01"; --inc
            nState    <= fsm_value_inc3;
            
          when fsm_value_inc3 =>
            DATA_EN <= '1';
            DATA_RDWR <= '1'; --print cur data
            prog_inc  <= '1'; -- next 
            nState  <= fsm_fetch;
    
          when fsm_value_dec =>
            mx1_sel <= '1'; -- look at data
            DATA_EN <= '1';
            nState <= fsm_value_dec1;

          when fsm_value_dec1 =>
            mx2_sel <= "10"; --dec
            DATA_EN <= '1';
            nState    <= fsm_value_dec2;

          when fsm_value_dec2 =>
            DATA_EN <= '1'; 
            DATA_RDWR <= '1'; --print
            prog_inc <= '1'; --next
            nState  <= fsm_fetch;
    
          when fsm_print =>
            mx1_sel <= '1'; --look at data
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get
            nState  <= fsm_print2;
    
          when fsm_print2 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0'; --get
            if OUT_BUSY = '1' then --wait until not busy 
              DATA_EN <= '1'; 
              DATA_RDWR <= '0';
              nState  <= fsm_print2;
            else
              OUT_DATA <= DATA_RDATA; --printout
              OUT_WE <= '1'; -- enable writing
              prog_inc <= '1'; -- next
              nState <= fsm_fetch;
            end if;

          when fsm_input =>
            mx1_sel <= '1'; -- get data
            mx2_sel <= "00"; -- data fom input
            nState    <= fsm_input2;

          when fsm_input2 =>
            IN_REQ    <= '1'; 
            if IN_VLD = '1' then -- wait until valid
              DATA_EN <= '1';
              DATA_RDWR <= '1'; --write&update
              prog_inc <= '1'; --next
              nState <= fsm_fetch;
              else
              nState <= fsm_input2; --get back & req data
            end if;
    
          when fsm_while_condition =>
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --when value is zero skip until ]
              mx1_sel <= '0'; --get prog data
              nState  <= fsm_while_skip;
            else
              prog_inc <= '1'; --move pointer
              nState  <= fsm_fetch;
            end if;
            
          when fsm_while_skip => --skip 
            DATA_EN <= '1'; --read prog data
            prog_inc <= '1'; -- move pointer
            if DATA_RDATA = x"5D" then --check for closing parse
              nState  <= fsm_fetch; --continue with the program
            else
              nState <= fsm_while_skip;
            end if;
            
            when fsm_while_end =>
            mx1_sel <= '1';--get prog data
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --continue with program
              prog_inc <= '1'; --move pointer
              nState <= fsm_fetch;  
            else
              mx1_sel <= '0';--get prog data
              nState <= fsm_while_repeat;
            end if;
            
          when fsm_while_repeat =>
            DATA_EN <= '1';
            if DATA_RDATA = x"5B" then --if [ start again  
              prog_inc <= '1';
              nState <= fsm_fetch;
            else
              prog_dec <= '1';
              mx1_sel <= '1';--get prog data
              nState <= fsm_while_end;
            end if;            
            
          when fsm_do_while_end =>
            DATA_EN <= '1'; --read ptr data
            if DATA_RDATA = "00000000" then --continue with program
              prog_inc <= '1'; --move pointer
              nState <= fsm_fetch;  
            else
              mx1_sel <= '0';--get prog data
              nState <= fsm_do_while_repeat;
            end if;
            
            when fsm_do_while_repeat =>
              DATA_EN <= '1';
            if DATA_RDATA = x"28" then --if ( start fetching again
              prog_inc <= '1';
              nState <= fsm_fetch;
            else
              prog_dec <= '1';
              nState <= fsm_do_while_repeat;  -- move back until (
            end if;            
            
          when fsm_null =>
            if RESET = '1' then
              nState <= fsm_start;
            end if;

          when others =>
            nState <= fsm_null;
        end case;

  end process;
---fsm---

  


end behavioral;

