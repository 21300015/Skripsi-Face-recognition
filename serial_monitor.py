import serial
import time
import sys
import argparse

def reset_esp(ser):
    print("Resetting ESP32...")
    ser.setDTR(False)
    ser.setRTS(False)
    time.sleep(0.1)
    ser.setDTR(False)
    ser.setRTS(True)  # EN=Low (Reset)
    time.sleep(0.1)
    ser.setRTS(False) # EN=High (Run)
    ser.setDTR(False) 
    print("Reset complete. Listening...")

def read_serial(port, baudrate, do_reset=False):
    ser = None
    try:
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"Connected to {port} at {baudrate} baud.")
        
        if do_reset:
            reset_esp(ser)

        print("Press Ctrl+C to exit.")
        
        while True:
            if ser.in_waiting > 0:
                try:
                    # Try decoding as utf-8, replace errors so we don't crash on garbage boot logs
                    data = ser.read(ser.in_waiting)
                    text = data.decode('utf-8', errors='replace')
                    print(text, end='') 
                except Exception as e:
                    print(f"\n[Read Error: {e}]")
            time.sleep(0.01)

    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
        print("Hint: Check if the port is correct and not open in another program.")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        if ser and ser.is_open:
            ser.close()
            print("Serial port closed.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Serial Monitor")
    parser.add_argument("port", nargs="?", default="COM6", help="Serial port (default: COM6)")
    parser.add_argument("baudrate", nargs="?", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--reset", action="store_true", help="Reset ESP32 on connect")
    
    args = parser.parse_args()
    
    # If users just pass arguments positionally without --reset, handle that:
    # (Argparse handles mixed well usually)
    
    read_serial(args.port, args.baudrate, args.reset)
