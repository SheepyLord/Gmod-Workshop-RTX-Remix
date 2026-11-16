#include "installation.hpp"
#ifdef _WIN32
#include <windows.h>
#else
#include "posix.hpp"
#include <dlfcn.h>
#include <unistd.h>
#endif
#include <algorithm>
#include <cwctype>
#include <functional>
#include <stdexcept>

namespace mmd {
// ---- paths for another server's scripts (installation.hpp; review finding 18) ----
namespace {
std::wstring plainPath(std::wstring s){
 if(s.starts_with(L"\\\\?\\UNC\\"))s=L"\\\\"+s.substr(8);else if(s.starts_with(L"\\\\?\\"))s=s.substr(4);
 while(s.size()>1&&(s.back()==L'\\'||s.back()==L'/'))s.pop_back();
 return s;
}
std::wstring folded(std::wstring s){
#ifdef _WIN32
 for(auto& c:s)c=wchar_t(std::towlower(c));
#endif
 return s;
}
std::string fileNameOf(const std::string& path){try{return utf8(fs::path(wide(path)).filename().wstring());}catch(...){return {};}}
}
std::string gameRelativePath(const fs::path& gameRoot,const std::string& text,bool marked){
 if(text.empty())return text;
 std::wstring path,root;
 try{path=plainPath(fs::path(wide(text)).lexically_normal().wstring());root=plainPath(gameRoot.lexically_normal().wstring());}catch(...){return {};}
 auto p=folded(path),r=folded(root);
 if(!r.empty()&&p.size()>r.size()+1&&p.compare(0,r.size(),r)==0&&(p[r.size()]==L'\\'||p[r.size()]==L'/'))
  return marked?"<game>"+utf8(path.substr(r.size())):utf8(path.substr(r.size()+1));
 return fileNameOf(text);
}
Json gameRelativeIdentity(const fs::path& gameRoot,Json identity){
 if(identity.is_object())for(auto key:{"path","expectedPath"})if(identity.contains(key)&&identity[key].is_string())identity[key]=gameRelativePath(gameRoot,identity[key].get<std::string>(),true);
 return identity;
}
Json withoutFolders(Json value,const std::vector<fs::path>& folders){
 std::vector<std::string> prefixes;
 for(auto& folder:folders)try{
  if(folder.empty())continue;
  for(auto& f:{utf8(folder.wstring()),utf8(plainPath(folder.wstring())),utf8(plainPath(folder.lexically_normal().wstring())),utf8(folder.generic_wstring())})if(!f.empty()){prefixes.push_back(f+"\\");prefixes.push_back(f+"/");}
 }catch(...){}
 // Longer spellings first: a \\?\ form would otherwise keep its prefix.
 std::sort(prefixes.begin(),prefixes.end(),[](const std::string& a,const std::string& b){return a.size()>b.size();});
 std::function<void(Json&)> walk=[&](Json& j){
  if(j.is_string()){auto s=j.get<std::string>();for(auto& f:prefixes)for(size_t at;(at=s.find(f))!=std::string::npos;)s.erase(at,f.size());j=s;}
  else if(j.is_structured())for(auto& item:j)walk(item);};
 walk(value);return value;
}
bool namesAbsolutePath(std::string_view s){return s.find(":\\")!=std::string_view::npos||s.find(":/")!=std::string_view::npos||s.find("\\\\")!=std::string_view::npos||s.find("/home/")!=std::string_view::npos;}
#ifndef _WIN32
// The game folder of the running executable: bin/linux64/gmod (the x86-64 branch's client),
// or a dedicated server's srcds_linux or bin/linux64/srcds_linux64.
static fs::path gameRoot(){
 auto folder=posix::executablePath().parent_path();
 if(folder.filename()=="linux64"&&folder.parent_path().filename()=="bin")return folder.parent_path().parent_path();
 if(folder.filename()=="bin")return folder.parent_path();
 return folder;
}
// Every Linux file sits in garrysmod/lua/bin: the modules find the runtime beside them ($ORIGIN).
Json componentIdentity(const char* component,const void* address){
 auto filename=posix::modulePath(address);
 auto expected=gameRoot()/"garrysmod"/"lua"/"bin"/(std::string(component)=="runtime"?MMDHL_RUNTIME_FILE:std::string(component)=="server"?MMDHL_SERVER_FILE:MMDHL_CLIENT_FILE);
 auto bytes=readFile(filename);
 return {{"component",component},{"release",MMDHL_RELEASE},{"build",MMDHL_BUILD_ID},{"installApi",MMDHL_INSTALL_API},{"api",ApiVersion},{"platform",MMDHL_PLATFORM},{"path",filename.string()},{"expectedPath",expected.lexically_normal().string()},{"sha256",hash(bytes)},{"size",bytes.size()}};
}
Json runtimeIdentity(){return componentIdentity("runtime",reinterpret_cast<const void*>(&runtimeIdentity));}
Json workerSelfTest(bool coacd){
 Json result={{"runtime",runtimeIdentity()},{"worker",true},{"coacd",false}};
 if(coacd){
  auto library=posix::executablePath().parent_path()/MMDHL_COACD_FILE;
  auto handle=dlopen(library.c_str(),RTLD_NOW|RTLD_LOCAL);
  if(!handle){auto why=dlerror();result["coacdError"]=std::string("Cannot load CoACD (")+(why?why:"unknown error")+").";}
  else{result["coacd"]=dlsym(handle,"CoACD_run")&&dlsym(handle,"CoACD_freeMeshArray");if(!result["coacd"].get<bool>())result["coacdError"]="CoACD exports do not match the supported ABI";dlclose(handle);}
 }
 return result;
}
Json probeWorker(const fs::path& bin,bool coacd){
 auto report=(posix::tempDirectory()/"mhiXXXXXX").string();int fd=mkstemp(report.data());
 if(fd<0)throw std::runtime_error("Cannot create worker diagnostic report");
 close(fd);struct Cleanup{std::string file;posix::Child child;~Cleanup(){child.kill();unlink(file.c_str());}} cleanup{report,{}};
 auto exe=bin/MMDHL_WORKER_FILE;std::vector<std::string> args{"--installation-test",report};if(coacd)args.push_back("coacd");
 try{cleanup.child=posix::spawn(exe,args,bin);}catch(const std::exception& e){throw std::runtime_error(std::string("Worker startup failed (")+e.what()+"). Check that the native files are complete and executable.");}
 if(!cleanup.child.wait(10000)){cleanup.child.kill();throw std::runtime_error("Worker self-test timed out after 10 seconds");}
 if(cleanup.child.exitCode)throw std::runtime_error("Worker self-test failed (exit "+std::to_string(cleanup.child.exitCode)+"). "+(cleanup.child.exitCode==127?std::string("A shared library it needs is missing, or the worker is not executable."):std::string("Check the native runtime and dependencies.")));
 return readJson(report);
}
#else
Json componentIdentity(const char* component,const void* address){
 HMODULE module=nullptr;wchar_t filename[32768];
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(address),&module)||!GetModuleFileNameW(module,filename,32768))throw std::runtime_error("Cannot locate loaded native component");
 wchar_t exe[32768];GetModuleFileNameW(nullptr,exe,32768);auto executable=fs::path(exe).parent_path();
 auto root=executable.filename()==L"win64"?executable.parent_path().parent_path():executable;
 // The x86-64 branch starts bin/win64/gmod.exe; the main branch (since 2026-09-17) starts
 // gmod_win64.exe in the game folder and loads the engine and this runtime from bin/win64.
 // srcds_win64.exe and the worker load it from beside themselves.
 auto runtimeFolder=lstrcmpiW(fs::path(exe).filename().c_str(),L"gmod_win64.exe")==0?executable/L"bin"/L"win64":executable;
 auto expected=std::string(component)=="runtime"?runtimeFolder/L"mmdhl_runtime_win64.dll":root/L"garrysmod"/L"lua"/L"bin"/(std::string(component)=="server"?L"gmsv_mmdhl_win64.dll":L"gmcl_mmdhl_win64.dll");
 auto bytes=readFile(filename);
 return {{"component",component},{"release",MMDHL_RELEASE},{"build",MMDHL_BUILD_ID},{"installApi",MMDHL_INSTALL_API},{"api",ApiVersion},{"platform","win64"},{"path",utf8(filename)},{"expectedPath",utf8(expected.wstring())},{"sha256",hash(bytes)},{"size",bytes.size()}};
}
Json runtimeIdentity(){return componentIdentity("runtime",reinterpret_cast<const void*>(&runtimeIdentity));}
Json workerSelfTest(bool coacd){
 Json result={{"runtime",runtimeIdentity()},{"worker",true},{"coacd",false}};
 if(coacd){
  wchar_t path[32768];GetModuleFileNameW(nullptr,path,32768);auto dll=fs::path(path).parent_path()/L"lib_coacd.dll";
  auto library=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if(!library)result["coacdError"]="Cannot load CoACD (Windows error "+std::to_string(GetLastError())+"). Install the Microsoft Visual C++ x64 Redistributable, including VCOMP140.";
  else{result["coacd"]=GetProcAddress(library,"CoACD_run")&&GetProcAddress(library,"CoACD_freeMeshArray");if(!result["coacd"].get<bool>())result["coacdError"]="CoACD exports do not match the supported ABI";FreeLibrary(library);}
 }
 return result;
}
Json probeWorker(const fs::path& bin,bool coacd){
 wchar_t temp[MAX_PATH],report[MAX_PATH];if(!GetTempPathW(MAX_PATH,temp)||!GetTempFileNameW(temp,L"mhi",0,report))throw std::runtime_error("Cannot create worker diagnostic report");
 struct Cleanup{wchar_t* path;HANDLE job=nullptr,process=nullptr,thread=nullptr;~Cleanup(){if(job)CloseHandle(job);if(thread)CloseHandle(thread);if(process)CloseHandle(process);DeleteFileW(path);}} cleanup{report};
 auto exe=bin/L"mmdhl_worker.exe";std::wstring command=L"\""+exe.wstring()+L"\" --installation-test \""+report+L"\""+(coacd?L" coacd":L"");
 cleanup.job=CreateJobObjectW(nullptr,nullptr);JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
 if(!cleanup.job||!SetInformationJobObject(cleanup.job,JobObjectExtendedLimitInformation,&limits,sizeof(limits)))throw std::runtime_error("Cannot contain worker diagnostic process");
 STARTUPINFOW start{};start.cb=sizeof(start);start.dwFlags=STARTF_USESHOWWINDOW;start.wShowWindow=SW_HIDE;PROCESS_INFORMATION process{};
 if(!CreateProcessW(exe.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW|CREATE_SUSPENDED,nullptr,bin.c_str(),&start,&process))throw std::runtime_error("Worker startup failed (Windows error "+std::to_string(GetLastError())+"). Check native dependencies and the Microsoft Visual C++ x64 Redistributable.");
 cleanup.process=process.hProcess;cleanup.thread=process.hThread;
 if(!AssignProcessToJobObject(cleanup.job,process.hProcess)){TerminateProcess(process.hProcess,1);throw std::runtime_error("Cannot contain worker diagnostic process");}
 ResumeThread(process.hThread);
 if(WaitForSingleObject(process.hProcess,10000)!=WAIT_OBJECT_0){TerminateJobObject(cleanup.job,1);WaitForSingleObject(process.hProcess,1000);throw std::runtime_error("Worker self-test timed out after 10 seconds");}
 DWORD exit=1;GetExitCodeProcess(process.hProcess,&exit);if(exit)throw std::runtime_error("Worker self-test failed (exit "+std::to_string(exit)+"). Check the native runtime and dependencies.");
 return readJson(report);
}
#endif
}
