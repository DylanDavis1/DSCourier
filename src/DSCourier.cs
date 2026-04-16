using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading.Tasks;
using Microsoft.Management.Configuration;
using WindowsPackageManager.Interop;

namespace DSCourier
{
    class DSCourier
    {
        static async Task<int> Main(string[] args)
        {
            try
            {
                if (args.Length == 0)
                {
                    Console.WriteLine("[!] Usage: DSCourier.exe <path-to-config.yaml>");
                    return 1;
                }

                if (!File.Exists(args[0]))
                {
                    Console.WriteLine($"[!] File not found: {args[0]}");
                    return 1;
                }

                string yamlContent = File.ReadAllText(args[0]);

                bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent())
                    .IsInRole(WindowsBuiltInRole.Administrator);
                Console.WriteLine($"[*] Running as admin: {isAdmin}");
                Console.WriteLine("[*] Applying via COM API - no winget.exe");

                await ApplyViaCOM(yamlContent, isAdmin);
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[!] Error: {ex.GetType().Name}: {ex.Message}");
                if (ex.InnerException != null)
                    Console.WriteLine($"[!] Inner: {ex.InnerException.Message}");
                if (ex.InnerException?.InnerException != null)
                    Console.WriteLine($"[!] Inner2: {ex.InnerException.InnerException.Message}");
                return 1;
            }
        }

        static async Task ApplyViaCOM(string yamlContent, bool isAdmin)
        {
            Console.WriteLine("[*] Creating WinGet factory...");
            WindowsPackageManagerFactory factory;
            if (isAdmin)
                factory = new WindowsPackageManagerElevatedFactory();
            else
                factory = new WindowsPackageManagerStandardFactory();
            Console.WriteLine("[*] Creating ConfigurationStaticFunctions...");
            var configStatics = factory.CreateConfigurationStaticFunctions();
            Console.WriteLine("[+] ConfigurationStaticFunctions created");
            Console.WriteLine("[*] Creating processor factory (pwsh)...");
            var processorFactory = await configStatics.CreateConfigurationSetProcessorFactoryAsync("pwsh");
            Console.WriteLine("[+] Processor factory created");
            Console.WriteLine("[*] Creating configuration processor...");
            var processor = configStatics.CreateConfigurationProcessor(processorFactory);
            processor.Caller = "DSCourier";
            processor.GenerateTelemetryEvents = false;
            Console.WriteLine("[+] Processor created");
            Console.WriteLine("[*] Opening configuration set...");
            var yamlBytes = System.Text.Encoding.UTF8.GetBytes(yamlContent);
            var memStream = new MemoryStream(yamlBytes);
            var inputStream = memStream.AsInputStream();

            var openResult = processor.OpenConfigurationSet(inputStream);
            var configSet = openResult.Set;

            if (configSet == null)
            {
                Console.WriteLine("[!] Failed to open configuration set");
                if (openResult.ResultCode != null)
                    Console.WriteLine($"[!] Error: {openResult.ResultCode.Message}");
                return;
            }

            Console.WriteLine($"[+] Opened - {configSet.Units.Count} units");
            foreach (var unit in configSet.Units)
            {
                Console.WriteLine($"    {unit.Type} [{unit.Identifier}]");
            }
            Console.WriteLine("[*] Applying...");
            var result = processor.ApplySet(configSet, ApplyConfigurationSetFlags.None);

            foreach (var ur in result.UnitResults)
            {
                var info = ur.ResultInformation;
                if (info.ResultCode != null && info.ResultCode.HResult != 0)
                    Console.WriteLine($"[!] {ur.Unit.Identifier}: FAILED (0x{info.ResultCode.HResult:X8})");
                else
                    Console.WriteLine($"[+] {ur.Unit.Identifier}: SUCCESS");
            }

            Console.WriteLine("[+] Done - no winget.exe was spawned");
        }
    }
}
