BATTERY DIAGNOSTIC CHECKER - FINAL

1. Keep these files together:
   - Check_Battery.bat
   - Battery_Diagnostic.ps1
   - Battery_Diagnostic.html

2. Double-click Check_Battery.bat.

3. The checker first reads Windows WMI/CIM battery data. If Design Capacity or Full Charge Capacity is missing, it automatically runs Microsoft's built-in powercfg /batteryreport and extracts the capacity values from that report.

4. It then calculates:
   Battery Health = Full Charge Capacity / Design Capacity x 100
   Capacity Loss  = 100 - Battery Health

5. The generated Battery_Report.html opens automatically.

This is intended for used-laptop inspection and resale testing. It reports capacity health; it does not certify physical battery safety, swelling, charger quality, or actual runtime.
