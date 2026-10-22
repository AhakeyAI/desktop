using System.Text.Json;
namespace AhaKey.Services;
// Generic durable envelope keeps Services independent from the physical Device assembly.
public sealed class OperationJournalStore(SettingsStore settings)
{
    private readonly object sync=new();
    public string DirectoryPath=>Path.Combine(settings.Root,"Operations");
    public void Persist<T>(Guid id,T record)
    {
        lock(sync){Directory.CreateDirectory(DirectoryPath);var path=Path.Combine(DirectoryPath,id.ToString("N")+".json");var temp=path+".tmp";
            using(var file=new FileStream(temp,FileMode.Create,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(file,record);file.Flush(true);}File.Move(temp,path,true);}
    }
    public string? ErrorKey {get;private set;}
    public IReadOnlyList<T> Read<T>()
    {
        lock(sync)
        {
            var result=new List<T>();ErrorKey=null;
            try
            {
                if(!Directory.Exists(DirectoryPath))return result;
                foreach(var path in Directory.EnumerateFiles(DirectoryPath,"*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(100))
                {
                    try{if(new FileInfo(path).Length>1024*1024)throw new JsonException();var value=JsonSerializer.Deserialize<T>(File.ReadAllText(path));if(value is not null)result.Add(value);else ErrorKey="OperationJournalUnreadable";}
                    catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or JsonException){ErrorKey="OperationJournalUnreadable";}
                }
            }
            catch(Exception ex)when(ex is IOException or UnauthorizedAccessException){ErrorKey="OperationJournalUnreadable";}
            return result;
        }
    }
}
