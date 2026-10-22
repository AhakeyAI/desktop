using System.Text.Json;
using AhaKey.Core;
namespace AhaKey.Services;

// Local authoring data only. Never a physical-device snapshot or synchronization proof.
public sealed class LocalDraftStore(SettingsStore settings)
{
    public string FilePath => Path.Combine(settings.Root,"local-draft.v1.json");
    public string? ErrorKey {get;private set;}
    private bool readOnly;
    public DeviceConfiguration? Load()
    {
        if(!File.Exists(FilePath))return null;
        try
        {
            var envelope=JsonSerializer.Deserialize<Envelope>(File.ReadAllText(FilePath))??throw new JsonException();
            if(envelope.Schema!=1)throw new JsonException();
            new DeviceCapabilities(true).Validate(envelope.Configuration);
            return envelope.Configuration;
        }
        catch(Exception ex) when(ex is JsonException or IOException or UnauthorizedAccessException or ArgumentException or NullReferenceException)
        {readOnly=true;ErrorKey="DraftLoadError";return null;}
    }
    public void Save(DeviceConfiguration configuration)
    {
        if(readOnly)return;
        var temporary=FilePath+".tmp";
        try
        {
            Directory.CreateDirectory(settings.Root);
            using(var file=new FileStream(temporary,FileMode.Create,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(file,new Envelope(1,configuration));file.Flush(true);}
            File.Move(temporary,FilePath,true);ErrorKey=null;
        }
        catch(Exception ex) when(ex is IOException or UnauthorizedAccessException){ErrorKey="DraftSaveError";}
    }
    public sealed record Envelope(int Schema,DeviceConfiguration Configuration);
}
