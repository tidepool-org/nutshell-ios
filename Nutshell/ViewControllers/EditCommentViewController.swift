/*
* Copyright (c) 2017, Tidepool Project
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
import MessageUI
import CocoaLumberjack

class EditCommentViewController: BaseUIViewController, UITextViewDelegate {

    
    @IBOutlet weak var editCommentSceneContainer: UIView!
    @IBOutlet weak var navItem: UINavigationItem!
    
    @IBOutlet weak var tableView: NutshellUITableView!

    // Configured by calling VC
    var note: BlipNote?             // must be set
    var commentToEdit: BlipNote?    // set if editing an existing comment
    var comments: [BlipNote] = []   // existing set of comments for the note
    // New comment returned to calling VC, if adding...
    var newComment: BlipNote?
    
    // Current "add comment" edit info, if edit in progress
    fileprivate var currentCommentEditCell: NoteListEditCommentCell?

    // Misc
    let dataController = NutDataController.sharedInstance

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = commentToEdit != nil ? "Edit Comment" : "Add Comment"
        
        // Add notification observers...
        let notificationCenter = NotificationCenter.default
        // graph data changes
        notificationCenter.addObserver(self, selector: #selector(EditCommentViewController.graphDataChanged(_:)), name: NSNotification.Name(rawValue: NewBlockRangeLoadedNotification), object: nil)
        // keyboard up/down
        notificationCenter.addObserver(self, selector: #selector(EditCommentViewController.keyboardWillShow(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
    }
   
    // delay manual layout until we know actual size of container view (at viewDidLoad it will be the current storyboard size)
    private var subviewsInitialized = false
    override func viewDidLayoutSubviews() {
        if (subviewsInitialized) {
            return
        }
        subviewsInitialized = true
        
        editCommentSceneContainer.setNeedsLayout()
        editCommentSceneContainer.layoutIfNeeded()
        self.tableView.rowHeight = UITableViewAutomaticDimension
        self.tableView.reloadData()
        
        // ensure row with edit is visible so keyboard will come up!
        self.tableView.scrollToRow(at: indexPathOfRowWithEdit(), at: .none, animated: false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    fileprivate var viewIsForeground: Bool = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewIsForeground = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewIsForeground = false
    }

    //
    // MARK: - View handling for keyboard
    //
    
    private var viewAdjustAnimationTime: TimeInterval = 0.25
    private var keyboardFrame: CGRect?
    
    // For add comment editing, scroll table so edit view is just above the keyboard when it opens.
    // Also captures keyboard sizing and appropriate scroll animation timing.
    func keyboardWillShow(_ notification: Notification) {
        NSLog("\(#function)")
        viewAdjustAnimationTime = notification.userInfo![UIKeyboardAnimationDurationUserInfoKey] as! TimeInterval
        keyboardFrame = (notification.userInfo![UIKeyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
        self.adjustKeyboardSpacerView() // first time, ensure we have a table footer for last cell special case
        self.adjustEditAboveKeyboard()
    }
 
    // Ensure there is enough table footer to allow add comment editing for last note
    fileprivate func adjustKeyboardSpacerView() {
        if let keyboardFrame = keyboardFrame {
            // add a footer view to the table that is the size of the keyboard, so last table row can be scrolled to the top of the table if necessary
            let height = keyboardFrame.height
            let curTableFooter = self.tableView.tableFooterView
            if curTableFooter != nil && curTableFooter!.bounds.height >= height {
                // table already adjusted...
                return
            }
            
            // add a footer view, possibly replace one that is too short (e.g., search keyboard is somewhat smaller than new comment edit keyboard)
            var footerFrame = self.tableView.bounds
            footerFrame.size.height = height
            let footerView = UIView(frame: footerFrame)
            footerView.backgroundColor = UIColor.white
            self.tableView.tableFooterView = footerView
        }
    }
    
    //
    // MARK: - Notes methods
    //
    
    func commentForIndexPath(_ indexPath: IndexPath) -> BlipNote? {
        let commentIndex = indexPath.row - 1
        if commentIndex < comments.count {
            return comments[commentIndex]
        }
        NSLog("\(#function): index \(indexPath) out of range of comment count \(comments.count)!!!")
        return nil
    }
    
    //
    // MARK: - Navigation
    //
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        super.prepare(for: segue, sender: sender)
    }
    
    /// Works with graphDataChanged to ensure graph is up-to-date after notification of database changes whether this VC is in the foreground or background.
    fileprivate func checkUpdateGraph() {
        NSLog("\(#function)")
        if graphNeedsUpdate {
            graphNeedsUpdate = false
            for cell in tableView.visibleCells {
                guard let graphCell = cell as? NoteListGraphCell else { continue }
                graphCell.updateGraph()
            }
        }
    }

    @IBAction func backButtonHandler(_ sender: Any) {
        performSegue(withIdentifier: "unwindFromEditComment", sender: self)
    }
    
    func editPressed(_ sender: NutshellSimpleUIButton!) {
        NSLog("cell with tag \(sender.tag) was pressed!")
        if APIConnector.connector().alertIfNetworkIsUnreachable() {
            return
        }
        
        // post new comment!
        if let currentEditCell = currentCommentEditCell {
            if let note = self.note {
                if let commentText = currentEditCell.addCommentTextView.text {
                    if commentText.isEmpty {
                        return
                    }
                    if let commentToEdit = self.commentToEdit {
                        // editing an existing comment
                        let newNote = BlipNote()
                        newNote.messagetext = commentText
                        newNote.timestamp = commentToEdit.timestamp
                        self.newComment = newNote
                        performSegue(withIdentifier: "unwindFromEditComment", sender: self)
                    } else {
                        // adding a new comment
                        let newNote = BlipNote()
                        newNote.user = dataController.currentLoggedInUser!
                        newNote.groupid = note.groupid
                        newNote.messagetext = commentText
                        newNote.parentmessage = note.id
                        newNote.userid = note.user!.userid
                        newNote.timestamp = Date()
                        self.newComment = newNote
                        performSegue(withIdentifier: "unwindFromAddComment", sender: self)
                    }
                }
            }
        }
    }

    //
    // MARK: - Graph support
    //

    fileprivate var graphNeedsUpdate: Bool  = false
    func graphDataChanged(_ note: Notification) {
        graphNeedsUpdate = true
        if viewIsForeground {
            NSLog("EventListVC: graphDataChanged, reloading")
            checkUpdateGraph()
        } else {
            NSLog("EventListVC: graphDataChanged, in background")
        }
    }
    

    //
    // MARK: - Add Comment UITextField Handling
    //
    
    func textViewDidChangeNotifyHandler(_ note: Notification) {
        if let textView = note.object as? UITextView {
            if textView == self.currentCommentEditCell?.addCommentTextView {
                NSLog("note changed to \(textView.text)")
            }
        }
    }
    
    
    // UITextViewDelegate methods
    func textViewDidChange(_ textView: UITextView) {
        NSLog("current content offset: \(tableView.contentOffset.y)")
        if let editCell = self.currentCommentEditCell {
            NSLog("note changed to \(textView.text)")
            var originalText = ""
            if let comment = self.commentToEdit {
                originalText = comment.messagetext
            }
            let enableSave = originalText != textView.text
            editCell.saveButton.isEnabled = enableSave
            editCell.saveButtonLargeHitArea.isEnabled = enableSave
            
            // adjust table if lines of text have changed...
            tableView.beginUpdates()
            tableView.endUpdates()
            adjustEditAboveKeyboard()
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView == self.currentCommentEditCell?.addCommentTextView {
            NSLog("\(#function)")
        }
    }

    private var animateOnAdjust = false
    func adjustEditAboveKeyboard() {
        if let curEditCell = currentCommentEditCell, let keyboardFrame = keyboardFrame {
            let cellContentOffset = curEditCell.frame.origin.y
            let sizeAboveKeyboard = tableView.bounds.height - keyboardFrame.height
            var targetOffset = tableView.contentOffset
            // minus 10 for 10 of the 12 note boundary separator pixels... 
            targetOffset.y = cellContentOffset - sizeAboveKeyboard  + curEditCell.bounds.height - 10.0
            if tableView.contentOffset.y < targetOffset.y {
                NSLog("setting table offset to \(targetOffset.y)")
                // Note: don't animate on first layout, too jumpy...
                tableView.setContentOffset(targetOffset, animated: animateOnAdjust)
                animateOnAdjust = true
            }
        }
    }

    
    //
    // MARK: - Table Misc
    //
    
    fileprivate let kNoteRow: Int = 0
    fileprivate let kGraphRow: Int = 1
    fileprivate let kPreCommentRows: Int = 2
    fileprivate let kDefaultAddCommentRow: Int = 2 // when there are no comments!
    fileprivate let kFirstCommentRow: Int = 2
    
    fileprivate func addCommentRow(commentCount: Int) -> Int {
        return kPreCommentRows + commentCount
    }

    func howToUploadPressed(_ sender: UIButton!) {
        NSLog("howToUploadPressed was pressed!")
        if let url = URL(string: "http://support.tidepool.org") {
            UIApplication.shared.openURL(url)
        }
    }

    fileprivate func indexPathOfRowWithEdit() -> IndexPath {
        var row = addCommentRow(commentCount: comments.count)
        if let commentToEdit = commentToEdit {
            for i in 0..<comments.count {
                if comments[i].id == commentToEdit.id {
                    row = kPreCommentRows + i
                    break
                }
            }
        }
        return IndexPath(row: row, section: 0)
    }
}

//
// MARK: - Table view delegate
//

extension EditCommentViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt estimatedHeightForRowAtIndexPath: IndexPath) -> CGFloat {
        return 90.0;
    }

    func tableView(_ tableView: UITableView, heightForRowAt heightForRowAtIndexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension;
    }
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }
    
}


//
// MARK: - Table view data source
//

extension EditCommentViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.note != nil ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // one row for note, one row for graph, one row per comment, one for add comment (unless we are just editing a comment)...
        let newCommentCount = commentToEdit != nil ? 0 : 1
        return self.comments.count + kPreCommentRows + newCommentCount
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if (indexPath.section != 0) {
            DDLogError("No note at cellForRowAt row \(indexPath.section)")
            return UITableViewCell()
        }
        
        let row = indexPath.row
        
        if row == kNoteRow {
            let group = dataController.currentViewedUser!
            let cellId = "noteListCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! NoteListTableViewCell
            cell.configureCell(note!, group: group)
            cell.editButton.isHidden = true
            return cell
        } else if row == kGraphRow {
            let cellId = "noteListGraphCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! NoteListGraphCell
            // graph does not have constraints, and since the cell hasn't been added to the parent table yet, size is storyboard size...
            cell.bounds.size.width = tableView.bounds.width
            cell.configureCell(note!)
            cell.configureGraphContainer()
            cell.howToUploadButton.addTarget(self, action: #selector(EditCommentViewController.howToUploadPressed(_:)), for: .touchUpInside)
            return cell
        } else {
            if row > addCommentRow(commentCount: comments.count) {
                DDLogError("Index past last row at cellForRowAt \(indexPath)")
                return UITableViewCell()
            }
            
            var comment: BlipNote? = nil
            var addOrEdit = false
            if row < kFirstCommentRow + comments.count {
                comment = comments[row-kFirstCommentRow]
                addOrEdit = comment?.id == self.commentToEdit?.id
            } else {
                addOrEdit = true
            }
            
            if addOrEdit {
                let cellId = "editCommentCell"
                let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! NoteListEditCommentCell
                cell.configureCell(note: comment, delegate: self)
                self.currentCommentEditCell = cell
                cell.saveButton.cellIndexPath = indexPath
                cell.saveButtonLargeHitArea.cellIndexPath = indexPath
                cell.saveButton.addTarget(self, action: #selector(EditCommentViewController.editPressed(_:)), for: .touchUpInside)
                cell.saveButtonLargeHitArea.addTarget(self, action: #selector(EditCommentViewController.editPressed(_:)), for: .touchUpInside)
                
                
                cell.addCommentTextView.perform(
                    #selector(becomeFirstResponder),
                    with: nil,
                    afterDelay: 0.25)
                return cell
            } else {
                if let comment = comment {
                    let cell = tableView.dequeueReusableCell(withIdentifier: "noteListCommentCell", for: indexPath) as! NoteListCommentCell
                    cell.configureCell(comment)
                    return cell
                } else {
                    DDLogError("No comment at cellForRowAt \(indexPath)")
                    return UITableViewCell()
                }
            }
        }
    }
}

