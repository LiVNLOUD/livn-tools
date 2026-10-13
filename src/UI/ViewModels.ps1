# Livn Tools - UI/ViewModels.ps1
# WPF baglama icin INotifyPropertyChanged destekli basit gorunum modelleri.
# .NET Framework 4.x csc derleyicisi C# 5 destekler: ?. / nameof / otomatik ozellik
# baslaticilari KULLANILMAZ.

$script:LtViewModelSource = @'
using System;
using System.ComponentModel;

namespace LivnTools.UI
{
    public abstract class Observable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    /// <summary>Bir ayar satiri. SECIM (Selected) ile SISTEM DURUMU (State*) ayri tutulur.</summary>
    public class TweakItem : Observable
    {
        private bool selected, isSupported = true, owned, hasDefault;
        private string stateText = "Okunuyor…", stateKind = "Loading", reason = "", details = "", lastResult = "", lastResultKind = "";

        public string Id { get; set; }
        public string Page { get; set; }
        public string GroupName { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public string Risk { get; set; }
        public string RiskText { get; set; }
        public string Evidence { get; set; }
        public string EvidenceText { get; set; }
        public string RestartText { get; set; }
        public string Exclusive { get; set; }
        public string Warning { get; set; }
        public string Sources { get; set; }

        public bool Selected { get { return selected; } set { if (selected != value) { selected = value; Raise("Selected"); } } }
        public bool IsSupported { get { return isSupported; } set { isSupported = value; Raise("IsSupported"); } }
        public bool Owned { get { return owned; } set { owned = value; Raise("Owned"); } }
        public bool HasDefault { get { return hasDefault; } set { hasDefault = value; Raise("HasDefault"); } }
        public string StateText { get { return stateText; } set { stateText = value; Raise("StateText"); } }
        public string StateKind { get { return stateKind; } set { stateKind = value; Raise("StateKind"); } }
        public string Reason { get { return reason; } set { reason = value; Raise("Reason"); Raise("HasReason"); } }
        public bool HasReason { get { return !String.IsNullOrEmpty(reason); } }
        public string Details { get { return details; } set { details = value; Raise("Details"); } }
        public string LastResult { get { return lastResult; } set { lastResult = value; Raise("LastResult"); Raise("HasLastResult"); } }
        public bool HasLastResult { get { return !String.IsNullOrEmpty(lastResult); } }
        public string LastResultKind { get { return lastResultKind; } set { lastResultKind = value; Raise("LastResultKind"); } }
        public string ToolTipText
        {
            get
            {
                string t = Description;
                if (!String.IsNullOrEmpty(Warning)) t += "\n\n⚠ " + Warning;
                if (!String.IsNullOrEmpty(details)) t += "\n\nMevcut durum:\n" + details;
                if (!String.IsNullOrEmpty(Sources)) t += "\n\nKaynak: " + Sources;
                return t;
            }
        }
        public void RefreshToolTip() { Raise("ToolTipText"); }
    }

    /// <summary>Geri alinamaz temizlik/bakim ogesi.</summary>
    public class CleanupItem : Observable
    {
        private bool selected, isAvailable = true;
        private string reason = "", lastResult = "", lastResultKind = "";
        public string Id { get; set; }
        public string Page { get; set; }
        public string GroupName { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public string Warning { get; set; }
        public bool LongRunning { get; set; }
        public bool Selected { get { return selected; } set { if (selected != value) { selected = value; Raise("Selected"); } } }
        public bool IsAvailable { get { return isAvailable; } set { isAvailable = value; Raise("IsAvailable"); } }
        public string Reason { get { return reason; } set { reason = value; Raise("Reason"); Raise("HasReason"); } }
        public bool HasReason { get { return !String.IsNullOrEmpty(reason); } }
        public string LastResult { get { return lastResult; } set { lastResult = value; Raise("LastResult"); Raise("HasLastResult"); } }
        public bool HasLastResult { get { return !String.IsNullOrEmpty(lastResult); } }
        public string LastResultKind { get { return lastResultKind; } set { lastResultKind = value; Raise("LastResultKind"); } }
        public string ToolTipText { get { return String.IsNullOrEmpty(Warning) ? Description : Description + "\n\n⚠ " + Warning; } }
    }

    /// <summary>Onizleme/sonuc listesi satiri.</summary>
    public class ReportRow
    {
        public string Title { get; set; }
        public string Kind { get; set; }
        public string KindText { get; set; }
        public string Message { get; set; }
        public string Changes { get; set; }
        public string Risk { get; set; }
        public bool HasChanges { get { return !String.IsNullOrEmpty(Changes); } }
    }

    public class Group
    {
        public string Name { get; set; }
        public System.Collections.ObjectModel.ObservableCollection<object> Items { get; private set; }
        public Group() { Items = new System.Collections.ObjectModel.ObservableCollection<object>(); }
    }
}
'@

function Initialize-LtViewModels {
    if (-not ('LivnTools.UI.TweakItem' -as [type])) {
        Add-Type -TypeDefinition $script:LtViewModelSource -Language CSharp -ErrorAction Stop
    }
}
