/*
* Copyright (c) 2015, Tidepool Project
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the associated License, which is identical to the BSD 2-Clause
* License as published by the Open Source Initiative at opensource.org.
*
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the License for more details.
*
* You should have received a copy of the License along with this program; if
* not, you can obtain one from Tidepool Project at tidepool.org.
*/

import UIKit
import CoreData

class EventListViewController: BaseUIViewController, ENSideMenuDelegate {

    @IBOutlet weak var menuButton: UIBarButtonItem!
    @IBOutlet weak var searchTextField: NutshellUITextField!
    @IBOutlet weak var searchPlaceholderLabel: NutshellUILabel!
    @IBOutlet weak var tableView: NutshellUITableView!
    @IBOutlet weak var coverView: UIControl!
    
    fileprivate var sortedNutEvents = [(String, NutEvent)]()
    fileprivate var filteredNutEvents = [(String, NutEvent)]()
    fileprivate var filterString = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "All events"
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()

        // Add a notification for when the database changes
        let moc = NutDataController.controller().mocForNutEvents()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(EventListViewController.databaseChanged(_:)), name: NSNotification.Name.NSManagedObjectContextObjectsDidChange, object: moc)
        notificationCenter.addObserver(self, selector: #selector(EventListViewController.textFieldDidChange), name: NSNotification.Name.UITextFieldTextDidChange, object: nil)

        if let sideMenu = self.sideMenuController()?.sideMenu {
            sideMenu.delegate = self
            menuButton.target = self
            menuButton.action = #selector(EventListViewController.toggleSideMenu(_:))
            let revealWidth = min(ceil((240.0/320.0) * self.view.bounds.width), 281.0)
            sideMenu.menuWidth = revealWidth
            sideMenu.bouncingEnabled = false
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    fileprivate var viewIsForeground: Bool = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewIsForeground = true
        configureSearchUI()
        if let sideMenu = self.sideMenuController()?.sideMenu {
            sideMenu.allowLeftSwipe = true
            sideMenu.allowRightSwipe = true
            sideMenu.allowPanGesture = true
       }
        
        if sortedNutEvents.isEmpty || eventListNeedsUpdate {
            eventListNeedsUpdate = false
            getNutEvents()
        }
        
        checkNotifyUserOfTestMode()
        // periodically check for authentication issues in case we need to force a new login
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.checkConnection()
        APIConnector.connector().trackMetric("Viewed Home Screen (Home Screen)")
    }
    
    // each first time launch of app, let user know we are still in test mode!
    fileprivate func checkNotifyUserOfTestMode() {
        if AppDelegate.testMode && !AppDelegate.testModeNotification {
            AppDelegate.testModeNotification = true
            let alert = UIAlertController(title: "Test Mode", message: "Nutshell has Test Mode enabled!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { Void in
                return
            }))
            alert.addAction(UIAlertAction(title: "Turn Off", style: .default, handler: { Void in
                AppDelegate.testMode = false
            }))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchTextField.resignFirstResponder()
        viewIsForeground = false
        if let sideMenu = self.sideMenuController()?.sideMenu {
            //NSLog("swipe disabled")
            sideMenu.allowLeftSwipe = false
            sideMenu.allowRightSwipe = false
            sideMenu.allowPanGesture = false
        }
    }

    @IBAction func toggleSideMenu(_ sender: AnyObject) {
        APIConnector.connector().trackMetric("Clicked Hamburger (Home Screen)")
        toggleSideMenuView()
    }

    //
    // MARK: - ENSideMenu Delegate
    //

    fileprivate func configureForMenuOpen(_ open: Bool) {
         if open {
            if let sideMenuController = self.sideMenuController()?.sideMenu?.menuViewController as? MenuAccountSettingsViewController {
                // give sidebar a chance to update
                // TODO: this should really be in ENSideMenu!
                sideMenuController.menuWillOpen()
            }
        }
        
        tableView.isUserInteractionEnabled = !open
        self.navigationItem.rightBarButtonItem?.isEnabled = !open
        coverView.isHidden = !open
    }
    
    func sideMenuWillOpen() {
        //NSLog("EventList sideMenuWillOpen")
        configureForMenuOpen(true)
    }
    
    func sideMenuWillClose() {
        //NSLog("EventList sideMenuWillClose")
        configureForMenuOpen(false)
    }
    
    func sideMenuShouldOpenSideMenu() -> Bool {
        //NSLog("EventList sideMenuShouldOpenSideMenu")
        return true
    }
    
    func sideMenuDidClose() {
        //NSLog("EventList sideMenuDidClose")
        configureForMenuOpen(false)
    }
    
    func sideMenuDidOpen() {
        //NSLog("EventList sideMenuDidOpen")
        configureForMenuOpen(true)
        APIConnector.connector().trackMetric("Viewed Hamburger Menu (Hamburger)")
    }

    //
    // MARK: - Navigation
    //
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        super.prepare(for: segue, sender: sender)
        if (segue.identifier) == EventViewStoryboard.SegueIdentifiers.EventGroupSegue {
            let cell = sender as! EventListTableViewCell
            let eventGroupVC = segue.destination as! EventGroupTableViewController
            eventGroupVC.eventGroup = cell.eventGroup!
            APIConnector.connector().trackMetric("Clicked a Meal (Home screen)")
        } else if (segue.identifier) == EventViewStoryboard.SegueIdentifiers.EventItemDetailSegue {
            let cell = sender as! EventListTableViewCell
            let eventDetailVC = segue.destination as! EventDetailViewController
            let group = cell.eventGroup!
            eventDetailVC.eventGroup = group
            eventDetailVC.eventItem = group.itemArray[0]
            APIConnector.connector().trackMetric("Clicked a Meal (Home screen)")
        } else if (segue.identifier) == EventViewStoryboard.SegueIdentifiers.HomeToAddEventSegue {
            APIConnector.connector().trackMetric("Click Add (Home screen)")
        } else {
            NSLog("Unprepped segue from eventList \(segue.identifier)")
        }
    }
    
    // Back button from group or detail viewer.
    @IBAction func done(_ segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventList done!")
    }

    // Multiple VC's on the navigation stack return all the way back to this initial VC via this segue, when nut events go away due to deletion, for test purposes, etc.
    @IBAction func home(_ segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventList home!")
    }

    // The add/edit VC will return here when a meal event is deleted, and detail vc was transitioned to directly from this vc (i.e., the Nut event contained a single meal event which was deleted).
    @IBAction func doneItemDeleted(_ segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventList doneItemDeleted")
    }

    @IBAction func cancel(_ segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventList cancel")
    }

    fileprivate var eventListNeedsUpdate: Bool  = false
    func databaseChanged(_ note: Notification) {
        NSLog("EventList: Database Change Notification")
        if viewIsForeground {
            getNutEvents()
        } else {
            eventListNeedsUpdate = true
        }
    }
    
    func getNutEvents() {

        var nutEvents = [String: NutEvent]()

        func addNewEvent(_ newEvent: EventItem) {
            /// TODO: TEMP UPGRADE CODE, REMOVE BEFORE SHIPPING!
            if newEvent.userid == nil {
                newEvent.userid = NutDataController.controller().currentUserId
                if let moc = newEvent.managedObjectContext {
                    NSLog("NOTE: Updated nil userid to \(newEvent.userid)")
                    moc.refresh(newEvent, mergeChanges: true)
                    _ = DatabaseUtils.databaseSave(moc)
                }
            }
            /// TODO: TEMP UPGRADE CODE, REMOVE BEFORE SHIPPING!

            let newEventId = newEvent.nutEventIdString()
            if let existingNutEvent = nutEvents[newEventId] {
                _ = existingNutEvent.addEvent(newEvent)
                //NSLog("appending new event: \(newEvent.notes)")
                //existingNutEvent.printNutEvent()
            } else {
                nutEvents[newEventId] = NutEvent(firstEvent: newEvent)
            }
        }

        sortedNutEvents = [(String, NutEvent)]()
        filteredNutEvents = [(String, NutEvent)]()
        filterString = ""
        
        // Get all Food and Activity events, chronologically; this will result in an unsorted dictionary of NutEvents.
        do {
            let nutEvents = try DatabaseUtils.getAllNutEvents()
            for event in nutEvents {
                //if let event = event as? Workout {
                //  NSLog("Event type: \(event.type), id: \(event.id), time: \(event.time), created time: \(event.createdTime!.timeIntervalSinceDate(event.time!)), duration: \(event.duration), title: \(event.title), notes: \(event.notes), userid: \(event.userid), timezone offset:\(event.timezoneOffset)")
                //}
                addNewEvent(event)
            }
        } catch let error as NSError {
            NSLog("Error: \(error)")
        }
        
        sortedNutEvents = nutEvents.sorted() { $0.1.mostRecent.compare($1.1.mostRecent as Date) == ComparisonResult.orderedDescending }
        updateFilteredAndReload()
        // One time orphan check after application load
        EventListViewController.checkAndDeleteOrphans(sortedNutEvents)
    }
    
    static var _checkedForOrphanPhotos = false
    class func checkAndDeleteOrphans(_ allNutEvents: [(String, NutEvent)]) {
        if _checkedForOrphanPhotos {
            return
        }
        _checkedForOrphanPhotos = true
        if let photoDirPath = NutUtils.photosDirectoryPath() {
            var allLocalPhotos = [String: Bool]()
            let fm = FileManager.default
            do {
                let dirContents = try fm.contentsOfDirectory(atPath: photoDirPath)
                //NSLog("Photos dir: \(dirContents)")
                if !dirContents.isEmpty {
                    for file in dirContents {
                        allLocalPhotos[file] = false
                    }
                    for (_, nutEvent) in allNutEvents {
                        for event in nutEvent.itemArray {
                            for url in event.photoUrlArray() {
                                if url.hasPrefix("file_") {
                                    //NSLog("\(NutUtils.photoInfo(url))")
                                    allLocalPhotos[url] = true
                                }
                            }
                        }
                    }
                }
            } catch let error as NSError {
                NSLog("Error accessing photos at \(photoDirPath), error: \(error)")
            }
            let orphans = allLocalPhotos.filter() { $1 == false }
            for (url, _) in orphans {
                NSLog("Deleting orphaned photo: \(url)")
                NutUtils.deleteLocalPhoto(url)
            }
        }
    }
    
    // MARK: - Search
    
    @IBAction func dismissKeyboard(_ sender: AnyObject) {
        searchTextField.resignFirstResponder()
    }
    
    func textFieldDidChange() {
        updateFilteredAndReload()
    }

    @IBAction func searchEditingDidEnd(_ sender: AnyObject) {
        configureSearchUI()
    }
    
    @IBAction func searchEditingDidBegin(_ sender: AnyObject) {
        configureSearchUI()
        APIConnector.connector().trackMetric("Typed into Search (Home Screen)")
    }
    
    fileprivate func searchMode() -> Bool {
        var searchMode = false
        if searchTextField.isFirstResponder {
            searchMode = true
        } else if let searchText = searchTextField.text {
            if !searchText.isEmpty {
                searchMode = true
            }
        }
        return searchMode
    }
    
    fileprivate func configureSearchUI() {
        let searchOn = searchMode()
        searchPlaceholderLabel.isHidden = searchOn
        self.title = searchOn && !filterString.isEmpty ? "Events" : "All events"
    }

    fileprivate func updateFilteredAndReload() {
        if !searchMode() {
            filteredNutEvents = sortedNutEvents
            filterString = ""
        } else if let searchText = searchTextField.text {
            if !searchText.isEmpty {
                if searchText.localizedCaseInsensitiveContains(filterString) {
                    // if the search is just getting longer, no need to check already filtered out items
                    filteredNutEvents = filteredNutEvents.filter() {
                        $1.containsSearchString(searchText)
                    }
                } else {
                    filteredNutEvents = sortedNutEvents.filter() {
                        $1.containsSearchString(searchText)
                    }
                }
                filterString = searchText
            } else {
                filteredNutEvents = sortedNutEvents
                filterString = ""
            }
            // Do this last, after filterString is configured
            configureSearchUI()
        }
        tableView.reloadData()
    }
}

//
// MARK: - Table view delegate
//

extension EventListViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt estimatedHeightForRowAtIndexPath: IndexPath) -> CGFloat {
        return 102.0;
    }

    func tableView(_ tableView: UITableView, heightForRowAt heightForRowAtIndexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension;
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let tuple = self.filteredNutEvents[indexPath.item]
        let nutEvent = tuple.1
        let cell = tableView.cellForRow(at: indexPath)
        if nutEvent.itemArray.count == 1 {
            self.performSegue(withIdentifier: EventViewStoryboard.SegueIdentifiers.EventItemDetailSegue, sender: cell)
        } else if nutEvent.itemArray.count > 1 {
            self.performSegue(withIdentifier: EventViewStoryboard.SegueIdentifiers.EventGroupSegue, sender: cell)
        }
    }

}

//
// MARK: - Table view data source
//

extension EventListViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredNutEvents.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        // Note: two different list cells are used depending upon whether a location will be shown or not. 
        var cellId = EventViewStoryboard.TableViewCellIdentifiers.eventListCellNoLoc
        var nutEvent: NutEvent?
        if (indexPath.item < filteredNutEvents.count) {
            let tuple = self.filteredNutEvents[indexPath.item]
            nutEvent = tuple.1
            
            if !nutEvent!.location.isEmpty {
                cellId = EventViewStoryboard.TableViewCellIdentifiers.eventListCellWithLoc
            }
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! EventListTableViewCell
        if let nutEvent = nutEvent {
            cell.configureCell(nutEvent)
        }
        return cell
    }

    /*
    // Override to support conditional editing of the table view.
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(tableView: UITableView, moveRowAtIndexPath fromIndexPath: NSIndexPath, toIndexPath: NSIndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

}
