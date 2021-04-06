import UIKit
import ARKit
import CoreMotion

class ViewController: UIViewController, SCNPhysicsContactDelegate {
    
    // Collision Categories used to know what collided with what
    // these cnstants are a sequenece of 2 to the power of {0,..n} so = (1,2,4,8...)
    //  Collision in ARKit is handled using bitmasks. Each type of object has its own bitmask and if they collide, the bitmasks can be compared.
    struct CollisionCategory: OptionSet {
        let rawValue: Int
        static let puckCategory = CollisionCategory(rawValue: 1 << 0) // use that because it is binary
        static let wallPlayer1Category = CollisionCategory(rawValue: 1 << 1)
        static let wallPlayer2Category = CollisionCategory(rawValue: 1 << 2)
        static let wallsForStriker = CollisionCategory(rawValue: 1 << 3)
        static let wallsForPuck = CollisionCategory(rawValue: 1 << 4)// walls which come from the both sides
        static let strikerCategory = CollisionCategory(rawValue: 1 << 5)
    }
    
    // IB Outlets
    @IBOutlet weak var highestScore: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var player1ScoreLabel: UILabel!
    @IBOutlet weak var startGameButton: UIButton!
    @IBOutlet weak var startGameOnSamePlaneButto: UIButton!
    @IBOutlet weak var livesLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var puckVelocityLabel: UILabel!
    @IBOutlet weak var youLostLabel: UIButton!
    @IBOutlet weak var moreInfoButton: UIButton!
    
    // Boolean variables
    var fieldAdded = false
    var puckAdded = false
    var lastTouchedIsStriker = true
    var lastTouchedIsWall2 = false
    var windowAdded = false
    var readyLeft = false
    var readyRight = false
    var invertedDirStriker = false
    
    // Global variable for main game scene
    var gameScene = SCNScene()
    
    // Global variables for scene nodes
    var puck = SCNNode()
    var striker1 = SCNNode()
    var wallPlayer1 = SCNNode()
    var wallPlayer2 = SCNNode()
    var wallPlayer2Prop = SCNNode()
    var floorPlane = SCNNode()
    var leftWallForPuck = SCNNode()
    var rightWallForPuck = SCNNode()
    var leftWallForStriker = SCNNode()
    var rightWallForStriker = SCNNode()
    var leftWallProp = SCNNode()
    var rightWallProp = SCNNode()
    var movingWindow = SCNNode()
    var movingWindow2 = SCNNode()
    let notification = UINotificationFeedbackGenerator()
    
    // Global variables for original x-axis positions of nodes
    var originalLeftWallForPuckPosition :Float = 0.0
    var originalRightWallForPuckPosition :Float = 0.0
    var originalLeftWallForStrikerPosition :Float = 0.0
    var originalrightWallForStrikerPosition :Float = 0.0
    var originalleftWallPropPosition :Float = 0.0
    var originalrightWallPropPosition :Float = 0.0
    var originalWallPlayer2PropPositionScale :Float = 0.0
    var originalfloorPlanePosition :Float = 0.0
    var originalfloorPlaneScale :Float = 0.0
    var originalWindow1Position :Float = 0.0
    var originalWindow2Position :Float = 0.0
    
    // Global variables needed for core motion (tilting function)
    var motion: CMMotionManager!
    var timer: Timer!
    var queue = OperationQueue() //  An operation queue executes its queued Operation objects based on their priority and readiness. After being added to an operation queue, an operation remains in its queue until it reports that it is finished with its task.
    
    
    // Global variables for game experience
    var currentLivesCount = 6
    var puckVelocity : Float = 1.5
    var stikerVelocity = 6.0
    
    // Global variable messageStatus that updates the messageLabel when the messageState is set
    var messageStatus = messageState.searchForPlanes {
        didSet {
            DispatchQueue.main.async { self.messageLabel.text = self.messageStatus.description }
        }
    }
    
    // messageState (hints) to be shown on messageLabel
    enum messageState: String,CustomStringConvertible {
        
        case searchForPlanes = "searchForPlanes",
        tapPlaneToPlaceField = "tapPlaneToPlaceField",
        ready = "ready",
        cautionPuckFaster = "cautionPuckFaster",
        fieldGotBigger = "fieldGotBigger",
        cautionWindowShake = "cautionWindowShake",
        cautionWindowTouchRightWall = "cautionWindowTouchRightWall",
        cautionWindowTouchLeftWall = "cautionWindowTouchLeftWall",
        cautionSlowedDownStricker = "cautionSlowedDownStricker",
        cautionInvertedDirection = "cautionInvertedDirection",
        normalTilting = "normalTilting"
        
        var description: String {
            switch self {
            case .searchForPlanes:
                return "👀 Look for a plane to place field"
            case .tapPlaneToPlaceField:
                return "🏒 Tap plane to place field!"
            case .ready:
                return "🥅 Press start or choose new plane"
            case .cautionPuckFaster:
                return "🏎 Increased velocity of puck"
            case .fieldGotBigger:
                return "😛 Increased field size"
            case .cautionWindowShake:
                return "📱👋 Shake Phone to remove wall"
            case .cautionWindowTouchLeftWall:
                return "👈 Move striker to left wall"
            case .cautionWindowTouchRightWall:
                return "👉 Move striker to right wall"
            case .cautionSlowedDownStricker:
                return "🐌 Slowed down striker"
            case .cautionInvertedDirection:
                return "🤪 Inverted tilting for striker!"
            case .normalTilting:
                return "🥳 Normal tilting activated again"
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addTapGestureToSceneView()
        sceneView.scene.physicsWorld.contactDelegate = self
        sceneView.scene.physicsWorld.timeStep = 1/300 //TimeStep is the time interval between updates to the physics simulation. The small this number is, the more accurate the physics simulation will be.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUpSceneView()
    }
    
    func setUpSceneView() {
        // Turn on plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        sceneView.delegate = self
        // Tet initial state of the UI (labels and buttons)
        youLostLabel.isHidden = true
        messageStatus = .searchForPlanes
        startGameButton.isHidden = true
        startGameOnSamePlaneButto.isHidden = true
        messageLabel.layer.masksToBounds = true
        messageLabel.layer.cornerRadius = 5
        setLivesLabel(for: currentLivesCount)
        highestScore.text = "\(UserDefaults().integer(forKey: "HIGHSCORE"))"
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // Shake phone to remove moving window feature
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?)
    {
        if event?.subtype == UIEvent.EventSubtype.motionShake && windowAdded == true
        {
            movingWindow.position.z += 30
            movingWindow.removeAllActions()
            movingWindow.position.x = originalWindow1Position
            windowAdded = false
            messageLabel.isHidden = true
        }
        
    }
    
    // Button that let's you choose new plane (removes all current nodes, updates UI and turns on plane detection)
    @IBAction func chooseNewPlaneButtonPressed(_ sender: UIButton) {
        sceneView.scene.rootNode.enumerateChildNodes {(node, stop) in node.removeFromParentNode()}
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        startGameButton.isHidden = true
        startGameOnSamePlaneButto.isHidden = true
        messageStatus = .searchForPlanes
        youLostLabel.isHidden = true
        messageLabel.isHidden = false
        fieldAdded = false
        puckAdded = false
        stikerVelocity = 6.0

    }
    
    // Start Game Button
    @IBAction func startGameOnSamePlaneButtonPressed(_ sender: UIButton) {
        // checks it puck/field isn't already placed (First time pressing start game)
        if puckAdded == false {
            addPuckToScene()
            startGameOnSamePlaneButto.isHidden = true
            startGameButton.isHidden = true
            messageLabel.isHidden = true
            puckVelocity = 1.5
            stikerVelocity = 6.0
            setVelocityLabel(for: puckVelocity)
        }
        // if puck is already in the scene we reset the fields size, the UI and restart the puck's movement
        else if puckAdded == true {
            // getting the field to the original/initial size
            leftWallForPuck.position.x = originalLeftWallForPuckPosition
            rightWallForPuck.position.x = originalRightWallForPuckPosition
            leftWallForStriker.position.x = originalLeftWallForStrikerPosition
            rightWallForStriker.position.x = originalrightWallForStrikerPosition
            leftWallProp.position.x = originalleftWallPropPosition
            rightWallProp.position.x = originalrightWallPropPosition
            wallPlayer2Prop.scale.x = originalWallPlayer2PropPositionScale
            floorPlane.position.x = originalfloorPlanePosition
            floorPlane.scale.x = originalfloorPlaneScale
            // reset the game experience variables & UI
            puckVelocity = 1.5
            stikerVelocity = 6.0
            setVelocityLabel(for: 1)
            currentLivesCount = 6
            setLivesLabel(for: currentLivesCount)
            messageLabel.isHidden = true
            // we use DispatchQueue to solve "use in main thread error"
            DispatchQueue.main.async {
                self.startGameButton.isHidden = true
                self.startGameOnSamePlaneButto.isHidden = true
                self.youLostLabel.isHidden = true
                self.player1ScoreLabel.text = "0"
                self.highestScore.text = "\(UserDefaults().integer(forKey: "HIGHSCORE"))"
            }
            // restart the puck's movement
            puck.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z)
            let number = Float.random(in: -1.5 ... 1.5)
            let direction = SCNVector3(number,0.0,-puckVelocity*2)
            puck.physicsBody?.applyForce(direction, asImpulse: true)
        }
        // hide the moreInfoButton when game is started
        moreInfoButton.isHidden = true
    }
    
    // Function that get's called when a found plane is touched
    @objc func addFieldToSceneView(withGestureRecognizer recognizer: UIGestureRecognizer) {
        if(fieldAdded == false){
            // First we remove all the nodes before placing the field
            sceneView.scene.rootNode.enumerateChildNodes { (node, stop) in node.removeFromParentNode()}
            let tapLocation = recognizer.location(in: sceneView)
            // We check if the hitResult is on an existingPlane
            let hitTestResults = sceneView.raycastQuery(from: tapLocation, allowing: .existingPlaneInfinite, alignment: .any)!
            let results = sceneView.session.raycast(hitTestResults)
//                .hitTest(tapLocation, types: .existingPlaneUsingExtent)
            guard let hitTestResult = results.first else { return }
//            let hitTestResults = sceneView.hitTest(tapLocation, types: .existingPlaneUsingExtent)
//            guard let hitTestResult = hitTestResults.first else { return }
            // getting and saving the plane position
            let anchor = sceneView.node(for: hitTestResult.anchor!)
            let x = (anchor?.simdPosition.x)! // indicating that the node is placed at the origin of the parent node’s coordinate system
            let y = (anchor?.simdPosition.y)!
            let z = (anchor?.simdPosition.z)!
            // getting all the self designed objects for field and setting them to their global variable
            gameScene = SCNScene(named: "gameField.scn")!
            leftWallForPuck = gameScene.rootNode.childNode(withName: "leftWallForPuck", recursively: false)!
            rightWallForPuck = gameScene.rootNode.childNode(withName: "rightWallForPuck", recursively: false)!
            leftWallForStriker = gameScene.rootNode.childNode(withName: "leftWallForStriker", recursively: false)!
            rightWallForStriker = gameScene.rootNode.childNode(withName: "rightWallForStriker", recursively: false)!
            leftWallProp = gameScene.rootNode.childNode(withName: "leftWallProp", recursively: false)!
            rightWallProp = gameScene.rootNode.childNode(withName: "rightWallProp", recursively: false)!
            striker1 = gameScene.rootNode.childNode(withName: "firstPlayerStriker", recursively: false)!
            wallPlayer1 = gameScene.rootNode.childNode(withName: "wallPlayer1", recursively: false)!
            wallPlayer2 = gameScene.rootNode.childNode(withName: "wallPlayer2", recursively: false)!
            floorPlane = gameScene.rootNode.childNode(withName: "floorPlane", recursively: false)!
            wallPlayer2Prop = gameScene.rootNode.childNode(withName: "wallPlayer2Prop", recursively: false)!
            // set the positions of all the nodes
            leftWallForPuck.position = SCNVector3(x,y,z)
            rightWallForPuck.position = SCNVector3(x,y,z)
            leftWallForStriker.position = SCNVector3(x,y,z)
            rightWallForStriker.position = SCNVector3(x,y,z)
            leftWallProp.position = SCNVector3(x,y,z)
            rightWallProp.position = SCNVector3(x,y,z)
            striker1.position = SCNVector3(x,y,z)
            wallPlayer1.position = SCNVector3(x,y,z)
            wallPlayer2.position = SCNVector3(x,y,z)
            floorPlane.position = SCNVector3(x,y,z)
            wallPlayer2Prop.position = SCNVector3(x,y,z)
            // saving the initial/original x-axis position for the nodes
            originalLeftWallForPuckPosition = leftWallForPuck.position.x
            originalRightWallForPuckPosition = rightWallForPuck.position.x
            originalLeftWallForStrikerPosition = leftWallForStriker.position.x
            originalrightWallForStrikerPosition = rightWallForStriker.position.x
            originalleftWallPropPosition = leftWallProp.position.x
            originalrightWallPropPosition = rightWallProp.position.x
            originalfloorPlanePosition = floorPlane.position.x
            // creating physics bodies for the different objects
            let physicsBodyleftWallForPuck = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: leftWallForPuck, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            let physicsBodyrightWallForPuck = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: rightWallForPuck, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            let physicsBodyleftWallForStriker = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: leftWallForStriker, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            let physicsBodyrightWallForStriker = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: rightWallForStriker, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            let physicsBodyStriker1 = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: striker1))
            let physicsBodyWallPlayer1 = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: wallPlayer1, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            let physicsBodyWallPlayer2 = SCNPhysicsBody(type: .kinematic,  shape: SCNPhysicsShape(node: wallPlayer2, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.convexHull]))
            // configuring the physics bodies
            configPhysicsBodyForWalls(physicsBody: physicsBodyleftWallForPuck)
            configPhysicsBodyForWalls(physicsBody: physicsBodyrightWallForPuck)
            configPhysicsBodyForWalls(physicsBody: physicsBodyleftWallForStriker)
            configPhysicsBodyForWalls(physicsBody: physicsBodyrightWallForStriker)
            configPhysicsBodyForStrikers(physicsBody: physicsBodyStriker1)
            configPhysicsBodyForWalls(physicsBody: physicsBodyWallPlayer1)
            configPhysicsBodyForWalls(physicsBody: physicsBodyWallPlayer2)
            // setting collision parameters for all physicsBodies
            setCollisonParametersForSideWallsForPuck(physicsBody: physicsBodyleftWallForPuck)
            setCollisonParametersForSideWallsForPuck(physicsBody: physicsBodyrightWallForPuck)
            setCollisonParametersForSideWallsForStriker(physicsBody: physicsBodyleftWallForStriker)
            setCollisonParametersForSideWallsForStriker(physicsBody: physicsBodyrightWallForStriker)
            setCollisonParametersForStriker(physicsBody: physicsBodyStriker1)
            setCollisonParametersForWallPlayers1(physicsBody: physicsBodyWallPlayer1)
            setCollisonParametersForWallPlayers2(physicsBody: physicsBodyWallPlayer2)
            // setting physics boodies to objects
            leftWallForPuck.physicsBody = physicsBodyleftWallForPuck
            rightWallForPuck.physicsBody = physicsBodyrightWallForPuck
            leftWallForStriker.physicsBody = physicsBodyleftWallForStriker
            rightWallForStriker.physicsBody = physicsBodyrightWallForStriker
            striker1.physicsBody = physicsBodyStriker1
            wallPlayer1.physicsBody = physicsBodyWallPlayer1
            wallPlayer2.physicsBody = physicsBodyWallPlayer2
            // saving the initial/original x-axis scale for the floor and wallPlayer2
            originalfloorPlaneScale = floorPlane.scale.x
            originalWallPlayer2PropPositionScale = wallPlayer2Prop.scale.x
            // adding nodes to the sceneView
            sceneView.scene.rootNode.addChildNode(leftWallForPuck)
            sceneView.scene.rootNode.addChildNode(rightWallForPuck)
            sceneView.scene.rootNode.addChildNode(leftWallForStriker)
            sceneView.scene.rootNode.addChildNode(rightWallForStriker)
            sceneView.scene.rootNode.addChildNode(leftWallProp)
            sceneView.scene.rootNode.addChildNode(rightWallProp)
            sceneView.scene.rootNode.addChildNode(striker1)
            sceneView.scene.rootNode.addChildNode(wallPlayer1)
            sceneView.scene.rootNode.addChildNode(wallPlayer2)
            sceneView.scene.rootNode.addChildNode(floorPlane)
            sceneView.scene.rootNode.addChildNode(wallPlayer2Prop)
            // sliding windows feature
            movingWindow = gameScene.rootNode.childNode(withName: "movingWindow", recursively: false)!
            movingWindow.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z + 30)
            originalWindow1Position = movingWindow.position.x
            sceneView.scene.rootNode.addChildNode(movingWindow)
            movingWindow2 = gameScene.rootNode.childNode(withName: "movingWindow2", recursively: false)!
            movingWindow2.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z + 30)
            originalWindow2Position = movingWindow2.position.x
            sceneView.scene.rootNode.addChildNode(movingWindow2)
            // start motion updates and set the lives and message label
            motion = CMMotionManager()
//            startDeviceMotion()
            startQueuedUpdates()
            // UI updates
            currentLivesCount = 6
            setLivesLabel(for: currentLivesCount)
            startGameButton.isHidden = false
            messageStatus = .ready
            startGameOnSamePlaneButto.isHidden = false
            youLostLabel.isHidden = true
            player1ScoreLabel.text = "0";
            highestScore.text = "\(UserDefaults().integer(forKey: "HIGHSCORE"))"
            // stop plane detection
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = []
            sceneView.session.run(configuration)
            // set global variable to know that field has been added
            fieldAdded = true
        } else {}
    }
    // function for configuring the field physicsbody
    func configPhysicsBodyForWalls(physicsBody : SCNPhysicsBody){
        physicsBody.allowsResting = true
        physicsBody.friction = 0.0
        physicsBody.restitution = 0.0
        physicsBody.mass = 1
    }
    // functions for configuring the striker's physicsbody
    func configPhysicsBodyForStrikers(physicsBody : SCNPhysicsBody){
        physicsBody.allowsResting = true
        physicsBody.friction = 0.0
        physicsBody.restitution = 0.0 // is it bouncing
        physicsBody.mass = 1
        physicsBody.velocityFactor = SCNVector3(1, 0, 0)
        physicsBody.angularVelocityFactor = SCNVector3(0, 0, 0)
    }
    // functions to configure the collision parameters for the nodes, needed for right collisions
    func setCollisonParametersForSideWallsForStriker(physicsBody : SCNPhysicsBody){
        physicsBody.categoryBitMask = CollisionCategory.wallsForStriker.rawValue
        physicsBody.contactTestBitMask =  CollisionCategory.strikerCategory.rawValue
        physicsBody.collisionBitMask =  CollisionCategory.strikerCategory.rawValue
    }
    func setCollisonParametersForSideWallsForPuck(physicsBody : SCNPhysicsBody){
        physicsBody.categoryBitMask = CollisionCategory.wallsForPuck.rawValue
        physicsBody.contactTestBitMask =  CollisionCategory.puckCategory.rawValue
        physicsBody.collisionBitMask =  CollisionCategory.puckCategory.rawValue
    }
    func setCollisonParametersForWallPlayers1(physicsBody : SCNPhysicsBody){
        physicsBody.categoryBitMask = CollisionCategory.wallPlayer1Category.rawValue
//        Every physics body in a scene can be assigned to one or more categories, each corresponding to a bit in the bit mask. You define the mask values used in your game.
        physicsBody.contactTestBitMask = CollisionCategory.puckCategory.rawValue
//        When two physics bodies overlap, a contact may occur. SceneKit compares the body’s contact mask to the other body’s category mask by performing a bitwise AND operation. If the result is a nonzero value, SceneKit creates an SCNPhysicsContact object describing the contact and sends messages to the contactDelegate object of the scene’s physics world.
        physicsBody.collisionBitMask = CollisionCategory.puckCategory.rawValue
//        When two physics bodies contact each other, a collision may occur. SceneKit compares the body’s collision mask to the other body’s category mask by performing a bitwise AND operation. If the result is a nonzero value, then the body is affected by the collision.
    }
    func setCollisonParametersForWallPlayers2(physicsBody : SCNPhysicsBody){
        physicsBody.categoryBitMask = CollisionCategory.wallPlayer2Category.rawValue
        physicsBody.contactTestBitMask = CollisionCategory.puckCategory.rawValue
        physicsBody.collisionBitMask = CollisionCategory.puckCategory.rawValue
    }
    func setCollisonParametersForStriker(physicsBody : SCNPhysicsBody){
        physicsBody.categoryBitMask = CollisionCategory.strikerCategory.rawValue
        physicsBody.contactTestBitMask = CollisionCategory.wallsForStriker.rawValue | CollisionCategory.puckCategory.rawValue
        physicsBody.collisionBitMask = CollisionCategory.wallsForStriker.rawValue | CollisionCategory.puckCategory.rawValue
    }
    
    // function that enables tap gesture to add field onto touched plane
    func addTapGestureToSceneView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.addFieldToSceneView(withGestureRecognizer:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
    }
    
    // Fetching device-motion data on demand
    func startDeviceMotion() {
        if motion.isDeviceMotionAvailable {
            self.motion.deviceMotionUpdateInterval = 1.0/60.0
            self.motion.showsDeviceMovementDisplay = true
            self.motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical) // this service provides separate values for user-initiated accelerations and for accelerations caused by gravity
            // Configure a timer to fetch the motion data.
            self.timer = Timer(fire: Date(), interval: (1.0/60.0), repeats: true, block: { (timer) in if let data = self.motion.deviceMotion {
                                    // tild to move striker with inverted direction feature build in
                                    let yaw = data.gravity.x * self.stikerVelocity
                                    var direction = SCNVector3(0,0,0)
                                    if self.invertedDirStriker == false {direction = SCNVector3(yaw,0,0)}
                                    else {direction = SCNVector3(-yaw,0,0)}
                                    self.striker1.physicsBody?.applyForce(direction, asImpulse: false)
                                }
            })
            // Add the timer to the current run loop.
            RunLoop.current.add(self.timer!, forMode: RunLoop.Mode.default)
        }
    }
    // Accessing queued motion data
    func startQueuedUpdates() {
        if motion.isDeviceMotionAvailable {
            self.motion.deviceMotionUpdateInterval = 1.0 / 60.0
            self.motion.showsDeviceMovementDisplay = true
            self.motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical,
                                                 to: self.queue, withHandler: { (data, error) in
                                                    // Make sure the data is valid before accessing it.
                                                    if let validData = data {
                                                        // tild to move striker with inverted direction feature build in
                                                        let yaw = (validData.gravity.x) * self.stikerVelocity
                                                        var direction = SCNVector3(0,0,0)
                                                        if self.invertedDirStriker == false {direction = SCNVector3(yaw,0,0)}
                                                        else {direction = SCNVector3(-yaw,0,0)}
                                                        self.striker1.physicsBody?.applyForce(direction, asImpulse: false)
                                                    }
            })
        }
    }

    // Tells the delegate that two bodies have come into contact.
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        checkCollisions(name1: contact.nodeA.name!, name2: contact.nodeB.name!)
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "leftWallForStriker" {
            removeWindowIfLeftWallIsHit()
        }
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "rightWallForStriker" {
            removeWindowIfRightWallIsHit()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "leftWallForStriker"{
            removeWindowIfLeftWallIsHit()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "rightWallForStriker"{
            removeWindowIfRightWallIsHit()
        }
    }
    
    // windows aren't actually 'removed', they're just moved back 30 meters to the back (+30 z-axis)
    func removeWindowIfLeftWallIsHit()
    {
        DispatchQueue.main.async {
            self.striker1.physicsBody?.clearAllForces()
            if self.readyLeft == true {
                self.movingWindow.position.z += 30
                self.movingWindow.removeAllActions()
                self.movingWindow.position.x = self.originalWindow1Position
                self.messageLabel.isHidden = true
                self.readyLeft = false
            }
        }
    }
    func removeWindowIfRightWallIsHit()
    {
        DispatchQueue.main.async {
            self.striker1.physicsBody?.clearAllForces()
            if self.readyRight == true {
                self.movingWindow2.position.z += 30
                self.movingWindow2.removeAllActions()
                self.movingWindow2.position.x = self.originalWindow2Position
                self.messageLabel.isHidden = true
                self.readyRight = false
            }
        }
    }
    // feature that makes field bigger by moving the side walls
    func makeFieldBigger() {
        messageStatus = .fieldGotBigger
        messageLabel.isHidden = false
        leftWallForPuck.position.x += -0.1
        rightWallForPuck.position.x += 0.1
        leftWallForStriker.position.x += -0.1
        rightWallForStriker.position.x += 0.1
        leftWallProp.position.x += -0.1
        rightWallProp.position.x += 0.1
        floorPlane.scale.x += 0.25
        wallPlayer2Prop.scale.x += 0.25
    }
    // feature that maked striker slower
    func makeStrikerSlower() {
        if(stikerVelocity > 3) {
            messageStatus = .cautionSlowedDownStricker
            messageLabel.isHidden = false
            stikerVelocity -= 0.5
        }
    }
    // feature that makes moving window appear and turn on shaking feature by setting the windowAdded variable to true
    func showWallShake() {
        movingWindow.position.z -= 30
        messageStatus = .cautionWindowShake
        messageLabel.isHidden = false
        addAnimationMoveRight(node: self.movingWindow)
        windowAdded = true
    }
    // feature that moving window dissapears if striker touched left wall
    func showWallLeft() {
        movingWindow.position.z -= 30
        messageStatus = .cautionWindowTouchLeftWall
        messageLabel.isHidden = false
        addAnimationMoveRight(node: self.movingWindow)
        readyLeft = true
    }
    // feature that moving window dissapears if striker touched right wall
    func showWallRight() {
        movingWindow2.position.z -= 30
        messageStatus = .cautionWindowTouchRightWall
        messageLabel.isHidden = false
        addAnimationMoveLeft(node: self.movingWindow2)
        readyRight = true
    }
    // function to check collisions, parameters are the names of the nodes that had collison
    func checkCollisions(name1 : String, name2 : String){
        if name2 == "puck" && (name1 == "wallPlayer1" || name1 == "wallPlayer2" || name1 == "firstPlayerStriker"){
            // if the puck has touched the invisible wallPlayer1 behind the striker
            if(name1 == "wallPlayer1"){
                /*
                We use lastTouchedIsWall2 variables so this function only runs this code once every time
                the puck hits the wall or striker, this is important because on collision between the puck
                and stiker/walls the physics world collision functions get called multiple times. This
                happens because the puck's physics shape is a concavePolyhedron and very precise so
                multiple individual faces of the polyhedron touch the walls at the same time
                We solve this by having a lastTouchedIsWall2 and lastTouchedIsStriker variable
                */
                if lastTouchedIsWall2 == true {
                    currentLivesCount = currentLivesCount - 1
                    setLivesLabel(for: currentLivesCount)
                    if currentLivesCount == 0 {
                        DispatchQueue.main.async {
                            self.notification.notificationOccurred(.error)
                            self.youLostLabel.isHidden = false
                            self.startGameButton.isHidden = false
                            self.startGameOnSamePlaneButto.isHidden = false
                            self.moreInfoButton.isHidden = false
                        }
                        puck.physicsBody?.clearAllForces()
                        puck.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z)
                        fieldAdded = false
                    } else {
                        putPuckBackonField()
                    }
                    lastTouchedIsWall2 = false
                }
                lastTouchedIsWall2 = false
                lastTouchedIsStriker = true
            }
            // if the puck has touched the invisible wallPlayer2 on the opposing side of the field
            if(name1 == "wallPlayer2"){
                if lastTouchedIsStriker == true  && lastTouchedIsWall2 == false {
                    DispatchQueue.main.async { self.player1ScoreLabel.text = String(Int(self.player1ScoreLabel.text!)! + 1);
                    // saving highest score when it has been changed
                    if Int(self.player1ScoreLabel.text!)! > UserDefaults().integer(forKey: "HIGHSCORE"){
                        UserDefaults.standard.set(Int(self.player1ScoreLabel.text!), forKey: "HIGHSCORE")
                        self.highestScore.text = "\(UserDefaults().integer(forKey: "HIGHSCORE"))"
                    }
                }
                DispatchQueue.main.async {
                    // set a local variable for the current score
                    let currentScore = Int(self.player1ScoreLabel.text!)!
                    // every ten points starting at 10 a random feature is activated only at 50 not
                    if(currentScore % 10 == 0 && currentScore != 50) {
                        self.selectRandomFeature()
                    }
                    // every ten points starting at 5 the puck's velocity is increased up to max 3.4 and it's not increased at 55
                    if(currentScore % 10 == 5 && self.puckVelocity <= 3.4 && currentScore != 55) {
                        self.messageStatus = .cautionPuckFaster
                        self.messageLabel.isHidden = false
                        self.puckVelocity += 0.3
                        self.setVelocityLabel(for: self.puckVelocity)
                    }
                    // reaching 50 points the user get's back 3 lives, puck is made slower and moving the striker is inverted until reaching 55 points
                    if(currentScore == 50) {
                        self.currentLivesCount += 3
                        self.setLivesLabel(for: self.currentLivesCount)
                        self.messageStatus = .cautionInvertedDirection
                        self.puckVelocity -= 0.9
                        self.setVelocityLabel(for: self.puckVelocity)
                        self.messageLabel.isHidden = false
                        self.invertedDirStriker = true
                    }
                    if(currentScore == 55) {
                        self.messageStatus = .normalTilting
                        self.invertedDirStriker = false
                    }
                }
                    // we set our boolean variables (explained above)
                    lastTouchedIsStriker = false
                    lastTouchedIsWall2 = true
                    // we stop the puck and apply a force back down to the striker (+ on the z-axis)
                    let direction = SCNVector3(0,0,puckVelocity)
                    puck.physicsBody?.velocity.z = 0
                    puck.physicsBody?.applyForce(direction, asImpulse: true)
                }
            }
            // if the puck has touched striker
            if(name1 == "firstPlayerStriker"){
                if lastTouchedIsStriker == false {
                // we stop the striker from moving on collision
                self.notification.notificationOccurred(.success)
                striker1.physicsBody?.clearAllForces()
                // we stop the puck and apply a force back down to the wall(- on the z-axis)
                let direction = SCNVector3(0,0,-puckVelocity)
                puck.physicsBody?.velocity.z = 0
                puck.physicsBody?.applyForce(direction, asImpulse: true)
                // we set our boolean variables (explained above)
                lastTouchedIsStriker = true
                lastTouchedIsWall2 = false
                }
            }
        }
    }
    
    // function that randomly selects what feature is used every 10 points
    func selectRandomFeature() {
        let number = Int.random(in: 0 ... 4)
        switch(number) {
        case 0:
            makeFieldBigger()
            break
        case 1:
            makeStrikerSlower()
            break
        case 2:
            showWallShake()
            break
        case 3:
            showWallLeft()
            break
        case 4:
            showWallRight()
            break
        default:
            break
        }
    }
    
    // function that updates the livesLabel
    func setLivesLabel(for currentLivesCount : Int){
        switch currentLivesCount {
        case 1:
            DispatchQueue.main.async { self.livesLabel.text = "❤️"}
        case 2:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️"}
        case 3:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️"}
        case 4:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️"}
        case 5:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️ ❤️"}
        case 6:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️ ❤️ ❤️"}
        case 7:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️"}
        case 8:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️"}
        case 9:
            DispatchQueue.main.async { self.livesLabel.text = "❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️ ❤️"}
        default:
            DispatchQueue.main.async { self.livesLabel.text = "☠️"}
        }
    }
    
    // function that updates the puckVelocityLabel
    func setVelocityLabel(for puckVelocity : Float){
        switch puckVelocity {
        case 1.3...1.6:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●○○○○○○"}
        case 1.7...1.9:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●○○○○○"}
        case 2.0...2.2:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●○○○○"}
        case 2.3...2.5:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●●○○○"}
        case 2.6...2.8:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●●●○○"}
        case 2.9...3.1:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●●●●○"}
        case 3.2...3.4:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●●●●●"}
        default:
            DispatchQueue.main.async { self.puckVelocityLabel.text = "●●●●●●●"}
        }
    }
    
    // Tells the delegate that new information is available about an ongoing contact.
    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) {
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "puck"{
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "puck"{
            striker1.physicsBody?.clearAllForces()
        }
    }
    
    // Tells the delegate that a contact has ended.
    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        // stop striker from bouncing on walls
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "leftWallForStriker" {
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "rightWallForStriker" {
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "leftWallForStriker"{
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "rightWallForStriker"{
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeA.name == "firstPlayerStriker" && contact.nodeB.name == "puck"{
            striker1.physicsBody?.clearAllForces()
        }
        if contact.nodeB.name == "firstPlayerStriker" && contact.nodeA.name == "puck"{
            striker1.physicsBody?.clearAllForces()
        }
    }
    
    // function to add puck to the scene
    func addPuckToScene() {
        // check if field is in the scene
        if(fieldAdded == true){
            // we define the puck node
            gameScene = SCNScene(named: "gameField.scn")!
            puck = gameScene.rootNode.childNode(withName: "puck", recursively: false)!
            puck.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z)
            // more precise puck,  performs physics calculations on physics bodies attached to nodes in the scene.
            let physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: puck, options: [SCNPhysicsShape.Option.type : SCNPhysicsShape.ShapeType.concavePolyhedron]))
            // configure the puck's physics body
            physicsBody.allowsResting = false
            physicsBody.isAffectedByGravity = false
            physicsBody.mass = 1
            physicsBody.angularVelocityFactor = SCNVector3(0, 0, 0) // to rotate
            physicsBody.velocityFactor = SCNVector3(1, 0, 1)
            physicsBody.restitution = 0.0 // make it bounce
            physicsBody.friction = 0.0
            physicsBody.categoryBitMask = CollisionCategory.puckCategory.rawValue
            physicsBody.contactTestBitMask = CollisionCategory.wallPlayer1Category.rawValue | CollisionCategory.wallPlayer2Category.rawValue | CollisionCategory.wallsForPuck.rawValue | CollisionCategory.strikerCategory.rawValue
            physicsBody.collisionBitMask = CollisionCategory.wallPlayer1Category.rawValue | CollisionCategory.wallPlayer2Category.rawValue | CollisionCategory.wallsForPuck.rawValue | CollisionCategory.strikerCategory.rawValue
            puck.physicsBody = physicsBody
            sceneView.scene.rootNode.addChildNode(puck)
            puckAdded = true
            /*
            launch the puck forward (- on the z-axis) to the wall with
            a random value on the x axis so every time a game starts the puck
            goes forward but on another angle
            */
            let number = Float.random(in: -1.5 ... 1.5)
            let direction = SCNVector3(number,0.0,-puckVelocity*2)
            puck.physicsBody?.applyForce(direction, asImpulse: true)
        }
    }
    // function we use to move puck back to middle of field and launch to the wall again
    func putPuckBackonField(){
            puck.position = SCNVector3(wallPlayer2.position.x,wallPlayer2.position.y,wallPlayer2.position.z)
            let number = Float.random(in: -1.5 ... 1.5)
            let direction = SCNVector3(number,0.0,-puckVelocity*2)
            puck.physicsBody?.applyForce(direction, asImpulse: true)
    }
    // press on the 'Best' button the screen to share yor score
    @IBAction func shareBestScoreButton(_ sender: Any) {
        let img = UIImage(named: "Logo")
        let messageStr = "Hey there, my highest score is \(highestScore.text ?? ""). Can you beat it ?"
        let activityViewController:UIActivityViewController = UIActivityViewController(activityItems:  [img!, messageStr], applicationActivities: nil)
        self.present(activityViewController, animated: true, completion: nil)
    }
    // function for moving window feature, moves the node 1.6 meters to the right with a duration of 15seconds
    func addAnimationMoveRight(node: SCNNode) {
        let moveOneMeter = SCNAction.moveBy(x: 1.6, y: 0, z: 0, duration: 15.0)
        node.runAction(moveOneMeter)
    }
    // function for moving window feature, moves the node 1.6 meters to the left with a duration of 15seconds
    func addAnimationMoveLeft(node: SCNNode) {
        let moveOneMeter = SCNAction.moveBy(x: -1.6, y: 0, z: 0, duration: 15.0)
        node.runAction(moveOneMeter)
    }
}

// custom color "transparentLightBlue" for showing plane
extension UIColor {
    open class var transparentLightBlue: UIColor {
        return UIColor(red: 90/255, green: 200/255, blue: 250/255, alpha: 0.50)
    }
}

extension ViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        // 1 We safely unwrap the anchor argument as an ARPlaneAnchor to make sure that we have information about a detected real world flat surface at hand.
        
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // 2 Here, we create an SCNPlane to visualize the ARPlaneAnchor. A SCNPlane is a rectangular “one-sided” plane geometry. We take the unwrapped ARPlaneAnchor extent’s x and z properties and use them to create an SCNPlane. An ARPlaneAnchor extent is the estimated size of the detected plane in the world. We extract the extent’s x and z for the height and width of our SCNPlane. Then we give the plane a transparent light blue color to simulate a body of water.
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        
        //let height = CGFloat(planeAnchor.extent.z)
        let plane = SCNPlane(width: width, height: height)
        
        // 3 We initialize a SCNNode with the SCNPlane geometry we just created.
        plane.materials.first?.diffuse.contents = UIColor.transparentLightBlue
        
        // 4 We initialize x, y, and z constants to represent the planeAnchor’s center x, y, and z position. This is for our planeNode’s position. We rotate the planeNode’s x euler angle by 90 degrees in the counter-clockerwise direction, else the planeNode will sit up perpendicular to the table. And if you rotate it clockwise, David Blaine will perform a magic illusion because SceneKit renders the SCNPlane surface using the material from one side by default.
        let planeNode = SCNNode(geometry: plane)
        
        // 5 Finally, we add the planeNode as the child node onto the newly added SceneKit node.
        
        let x = CGFloat(planeAnchor.center.x)
        let y = CGFloat(planeAnchor.center.y)
        let z = CGFloat(planeAnchor.center.z)
        planeNode.position = SCNVector3(x,y,z)
        planeNode.eulerAngles.x = -.pi / 2
        
        node.addChildNode(planeNode)
        // after having added plane set the planeStatus to ready
        messageStatus = .tapPlaneToPlaceField
    }
    
    func renderer(_ renderer: SCNSceneRenderer,   node: SCNNode, for anchor: ARAnchor) {
        
//        expand our previously detected horizontal plane(s) to make use of a larger surface or have a more accurate representation with the new information.
        
        // 1 First, we safely unwrap the anchor argument as ARPlaneAnchor. Next, we safely unwrap the node’s first child node. Lastly, we safely unwrap the planeNode’s geometry as SCNPlane. We are simply extracting the previously implemented ARPlaneAnchor, SCNNode, and SCNplaneand updating its properties with the corresponding arguments.
        guard let planeAnchor = anchor as?  ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane
            else { return }
        
        // 2 Here we update the plane’s width and height using the planeAnchor extent’s x and z properties.
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        // let width = CGFloat(planeAnchor.extent.x)
        // let height = CGFloat(planeAnchor.extent.z)
        plane.width = width
        plane.height = height
        
        // 3 At last, we update the planeNode’s position to the planeAnchor’s center x, y, and z coordinates.
        let x = CGFloat(planeAnchor.center.x)
        let y = CGFloat(planeAnchor.center.y)
        let z = CGFloat(planeAnchor.center.z)
        planeNode.position = SCNVector3(x, y, z)
    }

}
